import SwiftUI
import WebKit
import Combine
import Foundation

// MARK: - Ideas Card + TradingView embed
struct IdeasCard: View {
    let symbol: String // coin symbol, e.g., BTC
    @Environment(\.openURL) private var openURL
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TradingView Ideas")
                .font(.headline)
                .foregroundColor(.white)
            TradingViewIdeasWebView(symbol: symbol)
                .frame(height: 420)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))
            HStack {
                Spacer()
                Button {
                    let url = URL(string: "https://www.tradingview.com/symbols/\(symbol)USD/ideas/")!
                    openURL(url)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                        Text("Open in TradingView")
                    }
                    .font(.footnote.weight(.semibold))
                }
            }
        }
    }
}

struct TradingViewIdeasWebView: UIViewRepresentable {
    let symbol: String

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.bounces = true
        webView.navigationDelegate = context.coordinator
        #if os(iOS)
        webView.overrideUserInterfaceStyle = .dark
        webView.scrollView.indicatorStyle = .white
        #endif
        webView.load(URLRequest(url: ideasURL()))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Reload to keep the path in sync with the symbol; the site is heavy, keep it simple
        uiView.evaluateJavaScript("document.readyState") { _, _ in
            uiView.load(URLRequest(url: ideasURL()))
        }
    }

    private func ideasURL() -> URL {
        let base = "https://www.tradingview.com/symbols/\(symbol)USD/ideas/"
        let path = base + "?theme=dark"
        return URL(string: path) ?? URL(string: "https://www.tradingview.com/ideas/crypto/")!
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Enforce dark theme and hide promos/sticky UI
            let js = """
            (function(){
              function applyDark(){
                try{ localStorage.setItem('theme','dark'); }catch(e){}
                try{ document.documentElement.setAttribute('data-theme','dark'); }catch(e){}
                try{ document.body && document.body.classList.add('theme-dark'); }catch(e){}
                try{
                  var meta = document.querySelector('meta[name=\"color-scheme\"]');
                  if(!meta){ meta = document.createElement('meta'); meta.name='color-scheme'; document.head.appendChild(meta); }
                  meta.content='dark';
                }catch(e){}
                var css = `
                  :root, html, body { background:#000 !important; color:#ddd !important; }
                  header, .header, .tv-header, .tv-header__link, [data-widget-type=\"promo\"], .js-header { display:none !important; }
                  .layout__area--header, .apply-dark-bg { background:#000 !important; }
                `;
                var style = document.getElementById('cs-dark-style');
                if(!style){ style = document.createElement('style'); style.id='cs-dark-style'; style.type='text/css'; style.appendChild(document.createTextNode(css)); document.head.appendChild(style); }
              }
              function hideBanners(){
                try{
                  document.querySelectorAll('a[href*="apps.apple.com"]').forEach(a=>{
                    let n=a; let steps=0;
                    while(n && n.parentElement && steps++<4){ n=n.parentElement; if(n.offsetHeight>60){ n.style.display='none'; break; } }
                  });
                  const sels = [
                    '[data-name=\"banner\"]','[data-widget-name=\"banner\"]','[class*=\"banner\"]',
                    '.tv-floating-toolbar','.js-idea-page__app-promo','.sticky','.stickyHeader',
                    '.tv-app-promo','.tv-widget-idea__promo','.tv-app-promo__wrapper','.tv-embed__promo','.tv-ideas-stream__promo'
                  ];
                  sels.forEach(s=>document.querySelectorAll(s).forEach(e=>e.style.display='none'));
                  try{ document.querySelectorAll('[class*=\"ad\"],[id*=\"ad\"]').forEach(e=>{ e.style.display='none'; if(e.remove) e.remove(); }); }catch(e){}
                }catch(e){}
              }
              applyDark(); hideBanners();
              const mo = new MutationObserver(()=>{ applyDark(); hideBanners(); });
              mo.observe(document.documentElement,{childList:true,subtree:true});
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}

// MARK: - Deep Dive sheet
struct DeepDiveSheetView: View {
    let symbol: String
    let price: Double
    let change24h: Double
    let sparkline: [Double]
    @State private var longForm: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(longForm)
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding()
            }
            .navigationTitle("AI Deep Dive")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Copy") {
                        #if os(iOS)
                        UIPasteboard.general.string = longForm
                        #endif
                    }
                }
            }
        }
        .onAppear { regenerate() }
    }

    private func regenerate() { longForm = buildDeepDive() }

    private func buildDeepDive() -> String {
        let p = price
        let dir = change24h >= 0 ? "up" : "down"
        let c = String(format: "%.2f%%", abs(change24h))
        let (s1, r1) = swingLevels(series: sparkline)
        let hi7 = sparkline.max() ?? p
        let lo7 = sparkline.min() ?? p
        let range7 = hi7 - lo7
        let pos = range7 > 0 ? (p - lo7) / range7 : 0.5
        let posText = String(format: "%.0f%%", pos * 100)
        let mom7 = percentChange(from: sparkline.first, to: sparkline.last)
        let momText = String(format: "%.1f%%", mom7)
        let vol = volatility(of: sparkline)
        let volText = String(format: "%.2f%%", vol)

        var lines: [String] = []
        lines.append("\(symbol) is \(dir) \(c) over the last 24h, trading near \(currency(p)).")
        lines.append("7D range: \(currency(lo7)) – \(currency(hi7)) (position ~\(posText)). 7D momentum: \(momText).")
        if let s1 = s1 { lines.append("Nearest support: \(currency(s1)).") }
        if let r1 = r1 { lines.append("Nearest resistance: \(currency(r1)).") }
        lines.append("Realized intraday volatility (approx.): \(volText).")
        lines.append("Note: Levels are heuristic from recent swing points; confirm with your own analysis.")
        return lines.joined(separator: "\n\n")
    }

    private func percentChange(from: Double?, to: Double?) -> Double {
        guard let f = from, let t = to, f > 0 else { return 0 }
        return (t - f) / f * 100
    }

    private func volatility(of series: [Double]) -> Double {
        guard series.count > 2 else { return 0 }
        var returns: [Double] = []
        for i in 1..<series.count {
            let a = series[i - 1]
            let b = series[i]
            if a > 0 && b > 0 { returns.append((b - a) / a) }
        }
        let mean = returns.reduce(0, +) / Double(max(1, returns.count))
        let varSum = returns.reduce(0) { $0 + pow($1 - mean, 2) }
        let std = sqrt(varSum / Double(max(1, returns.count - 1)))
        return std * 100
    }

    private func swingLevels(series: [Double]) -> (Double?, Double?) {
        guard series.count >= 10 else { return (nil, nil) }
        let window = Array(series.suffix(96))
        var lows: [Double] = []
        var highs: [Double] = []
        if window.count >= 3 {
            for i in 1..<(window.count - 1) {
                let a = window[i - 1]
                let b = window[i]
                let c = window[i + 1]
                if b < a && b < c { lows.append(b) }
                if b > a && b > c { highs.append(b) }
            }
        }
        let s = lows.max()
        let r = highs.min()
        return (s, r)
    }

    private func currency(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return "$" + (f.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v))
    }
}

// MARK: - Notes editor
struct NotesEditorSheet: View {
    let symbol: String
    @State var text: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    init(symbol: String, initialText: String, onSave: @escaping (String) -> Void) {
        self.symbol = symbol
        self._text = State(initialValue: initialText)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .padding()
                .navigationTitle("Notes · \(symbol)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") { onSave(text); dismiss() }
                            .bold()
                    }
                }
        }
    }
}

// MARK: - In-app News (lightweight headlines)
struct NewsLinksList: View {
    let symbol: String
    @Environment(\.openURL) private var openURL
    var body: some View {
        VStack(spacing: 8) {
            linkRow(title: "Google News", url: "https://news.google.com/search?q=\(symbol)%20crypto")
            linkRow(title: "Bing News", url: "https://www.bing.com/news/search?q=\(symbol)%20crypto")
            linkRow(title: "CoinDesk", url: "https://www.coindesk.com/search/?q=\(symbol)")
            linkRow(title: "CoinTelegraph", url: "https://cointelegraph.com/tags/\(symbol.lowercased())")
            linkRow(title: "X (Twitter) Search", url: "https://x.com/search?q=\(symbol)%20crypto&src=typed_query")
        }
    }
    private func linkRow(title: String, url: String) -> some View {
        Button {
            if let u = URL(string: url) { openURL(u) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "arrow.up.right.square")
                Text(title)
                Spacer()
            }
            .font(.footnote.weight(.semibold))
            .foregroundColor(.white.opacity(0.9))
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }
}

struct NewsTab: View {
    let symbol: String
    @State private var selected: CoinNewsCategory = .top
    @StateObject private var vm = CoinNewsViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CoinNewsCategoryChips(selected: $selected)
            if vm.isLoading {
                ProgressView().tint(.white)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            }
            if vm.articles.isEmpty && !vm.isLoading {
                VStack(spacing: 10) {
                    Text("No headlines right now.")
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.8))
                    NewsLinksList(symbol: symbol)
                }
            } else {
                VStack(spacing: 8) {
                    ForEach(vm.articles.prefix(6)) { a in
                        ArticleRow(article: a)
                    }
                }
            }
            HStack {
                Spacer()
                Link(destination: vm.moreURL(for: symbol, category: selected)) {
                    HStack(spacing: 6) {
                        Image(systemName: "safari")
                        Text("More on Google News")
                    }
                    .font(.footnote.weight(.semibold))
                }
            }
        }
        .onAppear { vm.fetch(symbol: symbol, category: selected) }
        .onChange(of: selected) { cat in vm.fetch(symbol: symbol, category: cat) }
    }
}

struct ArticleRow: View {
    let article: NewsArticle
    @Environment(\.openURL) private var openURL
    var body: some View {
        Button {
            if let url = URL(string: article.link) { openURL(url) }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                if let url = article.imageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08))
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08))
                        @unknown default:
                            RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08))
                        }
                    }
                    .frame(width: 54, height: 54)
                    .clipped()
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.10), lineWidth: 0.6))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(article.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                    HStack(spacing: 8) {
                        if let src = article.source, !src.isEmpty {
                            Text(src)
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.6))
                        Text(article.relativeTime)
                            .font(.caption2)
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }
}

struct NewsArticle: Identifiable {
    let id = UUID()
    let title: String
    let link: String
    let pubDate: Date
    let source: String?
    let imageURL: URL?
    var relativeTime: String {
        let interval = Date().timeIntervalSince(pubDate)
        let minutes = Int(interval / 60)
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        return "\(hours/24)d"
    }
}

final class CoinNewsViewModel: ObservableObject {
    @Published var articles: [NewsArticle] = []
    @Published var isLoading: Bool = false

    private static var cache: [String: (Date, [NewsArticle])] = [:]
    private let cacheTTL: TimeInterval = 10 * 60

    func fetch(symbol: String, category: CoinNewsCategory) {
        let key = symbol.uppercased() + "|" + category.rawValue
        if let (ts, items) = Self.cache[key], Date().timeIntervalSince(ts) < cacheTTL {
            self.articles = items
            self.isLoading = false
            return
        }
        isLoading = true
        let url = feedURL(for: symbol, category: category)
        Task { @MainActor in
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let items = GoogleNewsRSSParser.parse(data: data)
                self.articles = items
                self.isLoading = false
                Self.cache[key] = (Date(), items)
            } catch {
                self.articles = []
                self.isLoading = false
            }
        }
    }

    func moreURL(for symbol: String, category: CoinNewsCategory) -> URL {
        let q = query(for: symbol, category: category).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? symbol
        return URL(string: "https://news.google.com/search?q=\(q)")!
    }

    private func feedURL(for symbol: String, category: CoinNewsCategory) -> URL {
        let q = query(for: symbol, category: category).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? symbol
        let path = "https://news.google.com/rss/search?q=\(q)&hl=en-US&gl=US&ceid=US:en"
        return URL(string: path)!
    }

    private func query(for symbol: String, category: CoinNewsCategory) -> String {
        return "\(symbol) \(category.queryKeywords)"
    }
}

enum GoogleNewsRSSParser {
    static func parse(data: Data) -> [NewsArticle] {
        let parser = _Parser()
        return parser.parse(data: data)
    }

    private final class _Parser: NSObject, XMLParserDelegate {
        private var items: [NewsArticle] = []
        private var currentTitle: String = ""
        private var currentLink: String = ""
        private var currentPubDate: Date = Date()
        private var currentElement: String = ""
        private var currentSource: String = ""
        private var currentImageLink: String = ""

        func parse(data: Data) -> [NewsArticle] {
            let xml = XMLParser(data: data)
            xml.delegate = self
            xml.parse()
            return items
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
            currentElement = elementName
            if elementName == "item" {
                currentTitle = ""; currentLink = ""; currentPubDate = Date()
                currentSource = ""; currentImageLink = ""
            }
            let name = elementName.lowercased()
            if name == "media:content" || name == "enclosure" || (qName?.lowercased() == "media:content") {
                if let url = attributeDict["url"], !url.isEmpty { currentImageLink = url }
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            switch currentElement {
            case "title": currentTitle += string
            case "link": currentLink += string
            case "pubDate": currentPubDate = parseDate(string) ?? currentPubDate
            case "source": currentSource += string
            default: break
            }
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            if elementName == "item" {
                let title = currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                let link = currentLink.trimmingCharacters(in: .whitespacesAndNewlines)
                let src = currentSource.trimmingCharacters(in: .whitespacesAndNewlines)
                let img = URL(string: currentImageLink.trimmingCharacters(in: .whitespacesAndNewlines))
                let article = NewsArticle(title: title, link: link, pubDate: currentPubDate, source: src.isEmpty ? nil : src, imageURL: (img?.scheme?.lowercased() == "https") ? img : nil)
                items.append(article)
            }
            currentElement = ""
        }

        private func parseDate(_ str: String) -> Date? {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
            return f.date(from: str.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}

// MARK: - Wrapper to reuse the Home premium news UI
struct CoinNewsEmbed: View {
    let symbol: String
    @StateObject private var vm = CryptoNewsFeedViewModel()
    @State private var lastSeenArticleID: String? = nil

    var body: some View {
        PremiumNewsSection(viewModel: vm, lastSeenArticleID: $lastSeenArticleID)
            .onAppear {
                vm.queryOverride = "\(symbol) crypto"
                vm.selectedSources = []
                vm.loadAllNews(force: true)
            }
            .onDisappear {
                vm.queryOverride = nil
            }
    }
}
