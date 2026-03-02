import SwiftUI
import WebKit
import Combine
import Foundation

// MARK: - Ideas Card + TradingView embed
struct IdeasCard: View {
    let symbol: String // coin symbol, e.g., BTC
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TradingView Ideas")
                .font(.headline)
                // LIGHT MODE FIX: Adaptive text
                .foregroundColor(DS.Adaptive.textPrimary)
            TradingViewIdeasWebView(symbol: symbol)
                .frame(height: 420)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1))
            HStack {
                Spacer()
                Button {
                    if let url = URL(string: "https://www.tradingview.com/symbols/\(symbol)USD/ideas/") {
                        openURL(url)
                    }
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
        
        // Inject script at document START to block Smart App Banner before it renders
        let bannerBlockScript = WKUserScript(
            source: """
            (function(){
                // Remove Smart App Banner meta tag immediately and continuously
                function removeAppBanner() {
                    document.querySelectorAll('meta[name="apple-itunes-app"]').forEach(m => m.remove());
                    document.querySelectorAll('meta[name="smartbanner"]').forEach(m => m.remove());
                }
                removeAppBanner();
                var observer = new MutationObserver(function(mutations) {
                    removeAppBanner();
                });
                if(document.documentElement) {
                    observer.observe(document.documentElement, {childList: true, subtree: true});
                }
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        config.userContentController.addUserScript(bannerBlockScript)
        
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

// MARK: - Deep Dive sheet (AI-Powered)
struct DeepDiveSheetView: View {
    let symbol: String
    let price: Double
    let change24h: Double
    let sparkline: [Double]
    let existingInsight: CoinAIInsight?
    var coinImageURL: URL? = nil
    
    @State private var aiAnalysis: String = ""
    @State private var isLoading: Bool = false
    @State private var justUpdated: Bool = false    // flash after deep dive replaces existing
    @State private var error: String? = nil
    @State private var cardsAppeared: Bool = false
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    /// Best available analysis: deep dive > cached deep dive > existing insight > local fallback
    private var displayAnalysis: String {
        if !aiAnalysis.isEmpty { return aiAnalysis }
        if let insight = existingInsight { return insight.insightText }
        return buildFallbackAnalysis()
    }
    
    /// Whether we have ANY AI content to show (avoids displaying the local fallback during loading)
    private var hasAIContent: Bool {
        !aiAnalysis.isEmpty || existingInsight != nil
    }
    
    /// Derived sentiment from price action
    private var sentimentLabel: String {
        if change24h > 3 { return "Bullish" }
        if change24h > 0.5 { return "Slightly Bullish" }
        if change24h > -0.5 { return "Neutral" }
        if change24h > -3 { return "Slightly Bearish" }
        return "Bearish"
    }
    private var sentimentColor: Color {
        if change24h > 0.5 { return .green }
        if change24h > -0.5 { return .orange }
        return .red
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(spacing: 0) {
                        // ── Premium Hero Header ──
                        deepDiveHero
                            .modifier(DeepDiveCardAppear(appeared: cardsAppeared, delay: 0))
                        
                        VStack(alignment: .leading, spacing: 14) {
                            // ── Technical Indicators ──
                            deepDiveTechnicals
                                .modifier(DeepDiveCardAppear(appeared: cardsAppeared, delay: 0.05))
                            
                            // ── Market Context ──
                            deepDiveContext
                                .modifier(DeepDiveCardAppear(appeared: cardsAppeared, delay: 0.1))
                            
                            // ── AI Analysis ──
                            deepDiveAISection
                                .modifier(DeepDiveCardAppear(appeared: cardsAppeared, delay: 0.15))
                            
                            Spacer(minLength: 20)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                    }
                }
            }
            .background(DS.Adaptive.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await loadDeepDive()
            }
            .onAppear {
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.4)) { cardsAppeared = true }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CSNavButton(
                        icon: "xmark",
                        action: { dismiss() },
                        accessibilityText: "Close",
                        accessibilityHintText: "Close AI Deep Dive",
                        compact: true
                    )
                }
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DS.Adaptive.gold)
                        Text("AI Deep Dive")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                    }
                }
            }
            .toolbarBackground(DS.Adaptive.background.opacity(0.95), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
    
    // MARK: - Hero Header
    private var deepDiveHero: some View {
        let hi7 = sparkline.max() ?? price
        let lo7 = sparkline.min() ?? price
        let range7 = hi7 - lo7
        let rawPos = range7 > 0 ? (price - lo7) / range7 : 0.5
        let pos = max(0, min(1, rawPos))
        let changeColor: Color = change24h >= 0 ? .green : .red
        
        return VStack(spacing: 0) {
            // ── Top section: Symbol, price, sparkline ──
            VStack(spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    // Coin icon
                    CoinImageView(
                        symbol: symbol,
                        url: coinImageURL,
                        size: 44
                    )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(symbol)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        Text(currency(price))
                            .font(.system(size: 26, weight: .heavy).monospacedDigit())
                            .foregroundColor(DS.Adaptive.textPrimary)
                    }
                    
                    Spacer()
                    
                    // Change badge + sentiment
                    VStack(alignment: .trailing, spacing: 6) {
                        HStack(spacing: 4) {
                            Image(systemName: change24h >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 11, weight: .bold))
                            Text(String(format: "%.2f%%", abs(change24h)))
                                .font(.system(size: 14, weight: .bold).monospacedDigit())
                        }
                        .foregroundColor(changeColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule().fill(changeColor.opacity(isDark ? 0.15 : 0.1))
                        )
                        
                        Text(sentimentLabel)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(sentimentColor.opacity(0.9))
                    }
                }
                
                // ── Mini sparkline chart ──
                if sparkline.count > 5 {
                    SparklineView(
                        data: sparkline,
                        isPositive: change24h >= 0,
                        overrideColor: changeColor,
                        height: 50,
                        lineWidth: SparklineConsistency.listLineWidth,
                        verticalPaddingRatio: SparklineConsistency.listVerticalPaddingRatio,
                        fillOpacity: SparklineConsistency.listFillOpacity * 0.32,
                        gradientStroke: true,
                        showEndDot: true,
                        leadingFade: 0.0,
                        trailingFade: 0.0,
                        showTrailHighlight: false,
                        trailLengthRatio: 0.0,
                        endDotPulse: false,
                        backgroundStyle: .none,
                        glowOpacity: SparklineConsistency.listGlowOpacity,
                        glowLineWidth: SparklineConsistency.listGlowLineWidth,
                        smoothSamplesPerSegment: SparklineConsistency.listSmoothSamplesPerSegment,
                        maxPlottedPoints: SparklineConsistency.listMaxPlottedPoints,
                        showBackground: false,
                        showExtremaDots: false,
                        neonTrail: false,
                        crispEnds: true,
                        horizontalInset: SparklineConsistency.listHorizontalInset,
                        compact: false,
                        seriesOrder: .oldestToNewest
                    )
                    .frame(height: 50)
                }
                
                // ── 7D Range bar ──
                VStack(spacing: 5) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color.red.opacity(0.25),
                                            Color.orange.opacity(0.15),
                                            Color.green.opacity(0.25)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(height: 5)
                            
                            Circle()
                                .fill(.white)
                                .frame(width: 9, height: 9)
                                .offset(x: max(0, min(geo.size.width - 9, CGFloat(pos) * (geo.size.width - 9))))
                        }
                    }
                    .frame(height: 9)
                    
                    HStack {
                        Text(currency(lo7))
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Spacer()
                        Text("7D Range · \(Int(pos * 100))%")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(DS.Adaptive.textSecondary)
                        Spacer()
                        Text(currency(hi7))
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 16)
            .background(
                ZStack {
                    DS.Adaptive.cardBackground
                    // Subtle gold gradient accent at top
                    LinearGradient(
                        colors: [
                            DS.Adaptive.gold.opacity(isDark ? 0.06 : 0.04),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            )
            
            // Thin separator line
            Rectangle()
                .fill(DS.Adaptive.divider)
                .frame(height: 0.5)
        }
    }
    
    // MARK: - Technicals Section
    private var deepDiveTechnicals: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                GoldHeaderGlyph(systemName: "chart.line.uptrend.xyaxis")
                Text("Technical Indicators")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
            }
            
            // Indicator grid
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                if sparkline.count >= 14, let rsi = TechnicalsEngine.rsi(sparkline, period: 14) {
                    DeepDiveIndicatorCell(
                        name: "RSI (14)",
                        value: String(format: "%.0f", rsi),
                        signal: rsi < 30 ? "Oversold" : (rsi > 70 ? "Overbought" : "Neutral"),
                        signalColor: rsi < 30 ? .green : (rsi > 70 ? .red : .yellow)
                    )
                }
                
                if sparkline.count >= 26,
                   let macdResult = TechnicalsEngine.macdLineSignal(sparkline) {
                    let m = macdResult.macd, s = macdResult.signal
                    DeepDiveIndicatorCell(
                        name: "MACD",
                        value: String(format: "%.4f", m - s),
                        signal: m > s ? "Bullish" : "Bearish",
                        signalColor: m > s ? .green : .red
                    )
                }
                
                let vol = volatility(of: sparkline)
                DeepDiveIndicatorCell(
                    name: "Volatility",
                    value: String(format: "%.2f%%", vol),
                    signal: vol > 5 ? "High" : (vol > 2 ? "Medium" : "Low"),
                    signalColor: vol > 5 ? .orange : (vol > 2 ? .yellow : .green)
                )
                
                let mom7 = percentChange(from: sparkline.first, to: sparkline.last)
                DeepDiveIndicatorCell(
                    name: "7D Momentum",
                    value: String(format: "%+.1f%%", mom7),
                    signal: mom7 > 5 ? "Strong" : (mom7 > 0 ? "Positive" : (mom7 > -5 ? "Negative" : "Weak")),
                    signalColor: mom7 > 0 ? .green : .red
                )
            }
            
            // Support / Resistance levels
            let (support, resistance) = swingLevels(series: sparkline, currentPrice: price)
            if support != nil || resistance != nil {
                HStack(spacing: 8) {
                    if let s = support {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.green)
                                .frame(width: 3, height: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Support")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(DS.Adaptive.textTertiary)
                                Text(currency(s))
                                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                                    .foregroundColor(.green)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.green.opacity(isDark ? 0.06 : 0.04))
                        )
                    }
                    if let r = resistance {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.red)
                                .frame(width: 3, height: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Resistance")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(DS.Adaptive.textTertiary)
                                Text(currency(r))
                                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                                    .foregroundColor(.red)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.red.opacity(isDark ? 0.06 : 0.04))
                        )
                    }
                }
                .padding(.top, 2)
            }
        }
        .modifier(DeepDiveCardStyle())
    }
    
    // MARK: - Market Context
    private var deepDiveContext: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                GoldHeaderGlyph(systemName: "globe")
                Text("Market Context")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
            }
            
            VStack(spacing: 0) {
                // Fear & Greed
                if let sentiment = ExtendedFearGreedViewModel.shared.currentValue,
                   let classification = ExtendedFearGreedViewModel.shared.currentClassificationKey {
                    VStack(spacing: 6) {
                        HStack {
                            Text("Fear & Greed Index")
                                .font(.system(size: 12))
                                .foregroundColor(DS.Adaptive.textSecondary)
                            Spacer()
                            HStack(spacing: 4) {
                                Text("\(sentiment)")
                                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                                    .foregroundColor(DS.Adaptive.textPrimary)
                                Text("(\(classification.capitalized))")
                                    .font(.system(size: 10))
                                    .foregroundColor(DS.Adaptive.textTertiary)
                            }
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                LinearGradient(
                                    colors: [.red, .orange, .yellow, .green],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(height: 5)
                                .clipShape(Capsule())
                                
                                Circle()
                                    .fill(.white)
                                    .frame(width: 9, height: 9)
                                    .offset(x: CGFloat(sentiment) / 100 * (geo.size.width - 9))
                            }
                        }
                        .frame(height: 9)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 10)
                    
                    deepDiveContextDivider
                }
                
                // BTC Dominance
                if let btcDom = MarketViewModel.shared.btcDominance {
                    deepDiveContextRow(
                        label: "BTC Dominance",
                        value: String(format: "%.1f%%", btcDom),
                        valueColor: DS.Adaptive.textPrimary
                    )
                    deepDiveContextDivider
                }
                
                // Market 24h
                if let globalChange = MarketViewModel.shared.globalChange24hPercent {
                    deepDiveContextRow(
                        label: "Market 24h",
                        value: String(format: "%+.2f%%", globalChange),
                        valueColor: globalChange >= 0 ? .green : .red
                    )
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isDark ? Color.white.opacity(0.02) : Color.black.opacity(0.015))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(DS.Adaptive.stroke.opacity(0.6), lineWidth: 0.5)
            )
        }
        .modifier(DeepDiveCardStyle())
    }
    
    private func deepDiveContextRow(label: String, value: String, valueColor: Color) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(DS.Adaptive.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundColor(valueColor)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
    }
    
    private var deepDiveContextDivider: some View {
        Rectangle()
            .fill(DS.Adaptive.divider.opacity(0.5))
            .frame(height: 0.5)
            .padding(.horizontal, 10)
    }
    
    // MARK: - AI Analysis Section
    
    private var deepDiveAISection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header row
            HStack(spacing: 7) {
                GoldHeaderGlyph(systemName: "sparkles")
                Text("CryptoSage AI Analysis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .allowsTightening(true)
                
                // Brief "Updated" badge after deep dive replaces stale insight
                if justUpdated {
                    Text("Updated")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.green)
                        .transition(.opacity)
                }
                
                Spacer()
                
                // Retry button — only when AI failed and we're not loading
                if error != nil && !hasAIContent && !isLoading {
                    Button {
                        Task { await loadDeepDive() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                            Text("Retry")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(DS.Adaptive.gold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(DS.Adaptive.gold.opacity(0.12)))
                        .overlay(Capsule().stroke(DS.Adaptive.gold.opacity(0.2), lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Error banner — only when AI failed and we have no content at all
            if error != nil && !hasAIContent {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    Text("AI unavailable — showing local analysis")
                        .font(.system(size: 10))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.orange.opacity(isDark ? 0.06 : 0.04))
                )
            }
            
            if isLoading && !hasAIContent {
                // No content at all — show shimmer while AI generates
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(0..<6, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(DS.Adaptive.chipBackground)
                            .frame(maxWidth: i == 5 ? 140 : (i == 3 ? 200 : .infinity))
                            .frame(height: 14)
                            .shimmer()
                    }
                }
            } else {
                deepDiveStructuredAnalysis
            }
            
            Text("AI-generated analysis for educational purposes only. Always do your own research.")
                .font(.system(size: 9))
                .foregroundColor(DS.Adaptive.textTertiary)
                .padding(.top, 4)
        }
        .modifier(DeepDiveCardStyle())
    }

    private enum DeepDiveSectionKind: String, CaseIterable {
        case summary = "Summary"
        case trend = "Trend"
        case risks = "Risks"
        case actionItems = "Next Steps"
    }

    private struct DeepDiveSection: Identifiable {
        let kind: DeepDiveSectionKind
        let body: String
        var id: DeepDiveSectionKind { kind }
    }

    private var deepDiveStructuredAnalysis: some View {
        let sections = parsedDeepDiveSections(from: displayAnalysis)
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(sections) { section in
                deepDiveSectionCard(section)
            }
        }
    }

    private func deepDiveSectionCard(_ section: DeepDiveSection) -> some View {
        let lines = normalizedSectionLines(from: section.body)
        let bulletLines = lines.filter { $0.hasPrefix("- ") }
        let paragraphLines = lines.filter { !$0.hasPrefix("- ") }

        return VStack(alignment: .leading, spacing: 6) {
            Text(section.kind.rawValue.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(DS.Adaptive.gold)
                .tracking(0.6)

            if !paragraphLines.isEmpty {
                Text(paragraphLines.joined(separator: " "))
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !bulletLines.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(bulletLines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .top, spacing: 6) {
                            Circle()
                                .fill(DS.Adaptive.gold.opacity(0.9))
                                .frame(width: 5, height: 5)
                                .padding(.top, 4)
                            Text(String(line.dropFirst(2)))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(DS.Adaptive.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(DS.Adaptive.stroke.opacity(0.55), lineWidth: 0.6)
        )
    }

    private func normalizedSectionLines(from text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func parsedDeepDiveSections(from rawText: String) -> [DeepDiveSection] {
        let normalized = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var buckets: [DeepDiveSectionKind: [String]] = [:]
        var unassigned: [String] = []
        var currentSection: DeepDiveSectionKind? = nil

        for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            if let detected = detectSectionKind(from: line) {
                currentSection = detected
                continue
            }

            if let currentSection {
                buckets[currentSection, default: []].append(line)
            } else {
                unassigned.append(line)
            }
        }

        if buckets.isEmpty || buckets.values.allSatisfy({ $0.isEmpty }) {
            let fallback = heuristicSectionSplit(from: normalized)
            for (k, v) in fallback {
                buckets[k, default: []] += v
            }
        } else if !unassigned.isEmpty {
            if buckets[.summary, default: []].isEmpty {
                buckets[.summary, default: []] += unassigned
            } else {
                buckets[.trend, default: []] += unassigned
            }
        }

        if buckets[.summary, default: []].isEmpty {
            buckets[.summary] = [summaryFallbackLine()]
        }
        if buckets[.trend, default: []].isEmpty {
            buckets[.trend] = [trendFallbackLine()]
        }
        if buckets[.risks, default: []].isEmpty {
            buckets[.risks] = [risksFallbackLine()]
        }
        if buckets[.actionItems, default: []].isEmpty {
            buckets[.actionItems] = actionFallbackLines()
        }

        rebalanceLongSummary(into: &buckets)

        return DeepDiveSectionKind.allCases.map { kind in
            DeepDiveSection(kind: kind, body: buckets[kind, default: []].joined(separator: "\n"))
        }
    }

    private func rebalanceLongSummary(into buckets: inout [DeepDiveSectionKind: [String]]) {
        let summaryText = buckets[.summary, default: []]
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summaryText.isEmpty else { return }

        let sentences = splitIntoSentences(summaryText)
        guard sentences.count > 2 else { return }

        let concise = Array(sentences.prefix(2)).joined(separator: " ")
        let overflow = Array(sentences.dropFirst(2)).joined(separator: " ")
        buckets[.summary] = [concise]
        if !overflow.isEmpty {
            buckets[.trend, default: []].insert(overflow, at: 0)
        }
    }

    private func splitIntoSentences(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if ch == "." || ch == "!" || ch == "?" {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { out.append(trimmed) }
                current.removeAll(keepingCapacity: true)
            }
        }
        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { out.append(tail) }
        return out
    }

    private func detectSectionKind(from line: String) -> DeepDiveSectionKind? {
        let canonical = line
            .lowercased()
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if canonical == "summary" || canonical.hasPrefix("summary ") { return .summary }
        if canonical.contains("action item") || canonical.contains("what to do") || canonical == "actions" {
            return .actionItems
        }
        if canonical.contains("risk") || canonical.contains("bearish case") || canonical.contains("bear case") {
            return .risks
        }
        if canonical.contains("technical") || canonical.contains("trend") || canonical.contains("market context") || canonical.contains("key levels") || canonical.contains("scenario") || canonical.contains("bullish case") {
            return .trend
        }
        return nil
    }

    private func heuristicSectionSplit(from normalized: String) -> [DeepDiveSectionKind: [String]] {
        let paragraphs = normalized
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !paragraphs.isEmpty else {
            return [:]
        }

        var out: [DeepDiveSectionKind: [String]] = [:]
        out[.summary] = [paragraphs[0]]

        let remaining = Array(paragraphs.dropFirst())
        if remaining.isEmpty { return out }

        var trendParts: [String] = []
        var riskParts: [String] = []
        var actionParts: [String] = []

        for paragraph in remaining {
            let lower = paragraph.lowercased()
            if lower.contains("risk") || lower.contains("bearish") || lower.contains("downside") || lower.contains("caution") || lower.contains("volatility") {
                riskParts.append(paragraph)
            } else if lower.contains("action") || lower.contains("watch") || lower.contains("consider") || lower.contains("set") || lower.contains("wait for") || lower.contains("if ") {
                actionParts.append(paragraph)
            } else {
                trendParts.append(paragraph)
            }
        }

        if !trendParts.isEmpty { out[.trend] = trendParts }
        if !riskParts.isEmpty { out[.risks] = riskParts }
        if !actionParts.isEmpty { out[.actionItems] = actionParts }
        return out
    }

    private func summaryFallbackLine() -> String {
        "\(symbol) is trading at \(currency(price)) with a 24h move of \(String(format: "%+.2f%%", change24h))."
    }

    private func trendFallbackLine() -> String {
        "Momentum and key levels are mixed. Confirm direction with a clean move above resistance or below support."
    }

    private func risksFallbackLine() -> String {
        "Risk remains elevated if momentum weakens or if price fails to hold nearby support levels."
    }

    private func actionFallbackLines() -> [String] {
        [
            "- Watch support and resistance levels for confirmation before entering.",
            "- Size positions conservatively while momentum remains mixed."
        ]
    }
    
    // MARK: - AI Loading
    
    /// Main entry point: cache-first, then existing insight, then generate.
    @MainActor
    private func loadDeepDive() async {
        let service = CoinAIInsightService.shared
        
        // 1. Check deep dive cache first — instant, no API call
        if let cached = service.cachedDeepDive(for: symbol, currentPrice: price, currentChange24h: change24h) {
            aiAnalysis = cached
            return // Done — no loading, no spinner, no API call
        }
        
        // 2. No cached deep dive. If we have an existing insight, show it
        //    immediately while we generate the deeper analysis in background.
        //    If we have nothing, show shimmer.
        let hasExisting = existingInsight != nil
        
        if !hasExisting {
            // Nothing to show — user sees shimmer
            isLoading = true
        }
        
        error = nil
        
        do {
            let analysis = try await service.generateDeepDive(
                symbol: symbol,
                price: price,
                change24h: change24h,
                change7d: percentChange(from: sparkline.first, to: sparkline.last),
                sparkline: sparkline
            )
            let wasShowingExisting = hasExisting && aiAnalysis.isEmpty
            withAnimation(.easeInOut(duration: 0.2)) {
                aiAnalysis = analysis
            }
            
            // Flash "Updated" briefly when deep dive replaces the old insight
            if wasShowingExisting {
                withAnimation(.easeInOut(duration: 0.15)) { justUpdated = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation(.easeInOut(duration: 0.3)) { justUpdated = false }
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    // MARK: - Helpers
    private func buildFallbackAnalysis() -> String {
        _ = change24h >= 0 ? "up" : "down"
        let verb = change24h >= 0 ? "gained" : "declined"
        let c = String(format: "%.2f%%", abs(change24h))
        let (s1, r1) = swingLevels(series: sparkline, currentPrice: price)
        let hi7 = sparkline.max() ?? price
        let lo7 = sparkline.min() ?? price
        let range7 = hi7 - lo7
        let pos = range7 > 0 ? (price - lo7) / range7 : 0.5
        _ = String(format: "%.0f%%", pos * 100)
        let mom7 = percentChange(from: sparkline.first, to: sparkline.last)
        let vol = volatility(of: sparkline)
        let volText = String(format: "%.2f%%", vol)
        
        var paragraphs: [String] = []
        
        // Opening summary
        paragraphs.append("\(symbol) has \(verb) \(c) over the past 24 hours and is currently trading near \(currency(price)).")
        
        // Price position context
        let posDesc: String
        if pos < 0.25 { posDesc = "near the bottom" }
        else if pos < 0.50 { posDesc = "in the lower half" }
        else if pos < 0.75 { posDesc = "in the upper half" }
        else { posDesc = "near the top" }
        paragraphs.append("The price sits \(posDesc) of its 7-day range (\(currency(lo7)) – \(currency(hi7))), with 7-day momentum at \(String(format: "%.1f%%", mom7)).")
        
        // Key levels
        var levelParts: [String] = []
        if let s = s1 { levelParts.append("support around \(currency(s))") }
        if let r = r1 { levelParts.append("resistance near \(currency(r))") }
        if !levelParts.isEmpty {
            paragraphs.append("Key levels to watch include \(levelParts.joined(separator: " and ")).")
        }
        
        // Volatility
        let volDesc: String
        if vol < 1.0 { volDesc = "relatively low" }
        else if vol < 3.0 { volDesc = "moderate" }
        else { volDesc = "elevated" }
        paragraphs.append("Realized 24h volatility is \(volDesc) at \(volText), suggesting \(vol < 1.5 ? "steady price action" : "potential for larger moves") in the near term.")
        
        return paragraphs.joined(separator: "\n\n")
    }

    private func percentChange(from: Double?, to: Double?) -> Double {
        guard let f = from, let t = to, f > 0 else { return 0 }
        return (t - f) / f * 100
    }

    private func volatility(of series: [Double]) -> Double {
        guard series.count > 2 else { return 0 }
        var returns: [Double] = []
        for i in 1..<series.count {
            let a = series[i - 1]; let b = series[i]
            if a > 0 && b > 0 { returns.append((b - a) / a) }
        }
        let mean = returns.reduce(0, +) / Double(max(1, returns.count))
        let varSum = returns.reduce(0) { $0 + pow($1 - mean, 2) }
        let std = sqrt(varSum / Double(max(1, returns.count - 1)))
        return std * 100
    }

    /// Fixed: filters relative to currentPrice so support < price < resistance
    private func swingLevels(series: [Double], currentPrice: Double) -> (Double?, Double?) {
        guard series.count >= 10 else { return (nil, nil) }
        let window = Array(series.suffix(96))
        var lows: [Double] = []
        var highs: [Double] = []
        if window.count >= 3 {
            for i in 1..<(window.count - 1) {
                let a = window[i - 1]; let b = window[i]; let c = window[i + 1]
                if b < a && b < c { lows.append(b) }
                if b > a && b > c { highs.append(b) }
            }
        }
        let s = lows.filter { $0 <= currentPrice }.max() ?? window.filter { $0 <= currentPrice }.max()
        let r = highs.filter { $0 >= currentPrice }.min() ?? window.filter { $0 >= currentPrice }.min()
        return (s, r)
    }

    private func currency(_ v: Double) -> String {
        if v >= 1 { return String(format: "$%.2f", v) }
        else if v >= 0.01 { return String(format: "$%.4f", v) }
        else { return String(format: "$%.6f", v) }
    }
}

// MARK: - Deep Dive Card Style
struct DeepDiveCardStyle: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(DS.Adaptive.cardBackground)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [DS.Adaptive.overlay(0.03), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 1)
            )
    }
}

// MARK: - Deep Dive Card Appear Animation
private struct DeepDiveCardAppear: ViewModifier {
    let appeared: Bool
    let delay: Double
    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
            .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(delay), value: appeared)
    }
}

// MARK: - Deep Dive Indicator Cell
struct DeepDiveIndicatorCell: View {
    let name: String
    let value: String
    let signal: String
    let signalColor: Color
    
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(DS.Adaptive.textTertiary)
            Text(value)
                .font(.system(size: 15, weight: .bold).monospacedDigit())
                .foregroundColor(DS.Adaptive.textPrimary)
            Text(signal)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(signalColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(signalColor.opacity(isDark ? 0.15 : 0.1))
                .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DS.Adaptive.stroke.opacity(0.6), lineWidth: 0.5)
        )
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
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: {
                            Text("Cancel")
                                .foregroundStyle(DS.Adaptive.textSecondary)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { onSave(text); dismiss() } label: {
                            Text("Save")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(BrandColors.goldBase)
                        }
                    }
                }
        }
    }
}

// MARK: - In-app News (lightweight headlines)
struct NewsLinksList: View {
    let symbol: String
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    // SECURITY FIX: URL encode user input to prevent injection
    private var encodedSymbol: String {
        symbol.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? symbol
    }
    
    var body: some View {
        VStack(spacing: 8) {
            linkRow(title: "Google News", url: "https://news.google.com/search?q=\(encodedSymbol)%20crypto")
            linkRow(title: "Bing News", url: "https://www.bing.com/news/search?q=\(encodedSymbol)%20crypto")
            linkRow(title: "CoinDesk", url: "https://www.coindesk.com/search/?q=\(encodedSymbol)")
            linkRow(title: "CoinTelegraph", url: "https://cointelegraph.com/tags/\(symbol.lowercased())")
            linkRow(title: "X (Twitter) Search", url: "https://x.com/search?q=\(encodedSymbol)%20crypto&src=typed_query")
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
            // LIGHT MODE FIX: Adaptive text and backgrounds
            .foregroundColor(isDark ? .white.opacity(0.9) : DS.Adaptive.textPrimary)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }
}

// Inserted replacement chips view for news categories
struct NewsCategoryChips: View {
    @Binding var selected: CoinNewsCategory
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(CoinNewsCategory.allCases, id: \.self) { cat in
                    chipButton(for: cat)
                }
            }
            .padding(.horizontal, 2)
        }
    }
    
    private func chipButton(for cat: CoinNewsCategory) -> some View {
        let isSelected = selected == cat
        let fillColor: Color = isDark
            ? (isSelected ? Color.white.opacity(0.16) : Color.white.opacity(0.06))
            : (isSelected ? Color.black.opacity(0.08) : Color.black.opacity(0.03))
        let strokeColor: Color = isDark ? Color.white.opacity(0.12) : Color.black.opacity(0.08)
        let textColor: Color = isDark ? .white : DS.Adaptive.textPrimary
        
        return Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            withAnimation(.easeInOut(duration: 0.18)) { selected = cat }
        } label: {
            Text(cat.rawValue)
                .font(.caption.weight(.semibold))
                .foregroundColor(textColor)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(fillColor)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(strokeColor, lineWidth: 0.8)
                )
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
            NewsCategoryChips(selected: $selected)
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
        .onAppear {
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async { vm.fetch(symbol: symbol, category: selected) }
        }
        .onChange(of: selected) { _, cat in
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async { vm.fetch(symbol: symbol, category: cat) }
        }
    }
}

struct ArticleRow: View {
    let article: NewsArticle
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }
    
    private var articleURL: URL? {
        URL(string: article.link)
    }
    
    var body: some View {
        Button {
            if let url = articleURL { openURL(url) }
        } label: {
            HStack(alignment: .center, spacing: 14) {
                // Use CachingAsyncImage for consistent thumbnail loading - 120x85 to match UnifiedNewsRow
                CachingAsyncImage(url: article.imageURL, referer: articleURL)
                    .frame(width: 120, height: 85)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            // LIGHT MODE FIX: Adaptive stroke
                            .stroke(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
                    )
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(article.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                    
                    HStack(spacing: 8) {
                        if let src = article.source, !src.isEmpty {
                            SourcePill(text: src)
                        }
                        Text(article.relativeTime)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            // LIGHT MODE FIX: Adaptive card backgrounds
            .background(RoundedRectangle(cornerRadius: 10).fill(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 0.8))
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
        return URL(string: "https://news.google.com/search?q=\(q)") ?? URL(string: "https://news.google.com")!
    }

    private func feedURL(for symbol: String, category: CoinNewsCategory) -> URL {
        let q = query(for: symbol, category: category).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? symbol
        let path = "https://news.google.com/rss/search?q=\(q)&hl=en-US&gl=US&ceid=US:en"
        return URL(string: path) ?? URL(string: "https://news.google.com/rss")!
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
    @ObservedObject private var vm = CryptoNewsFeedViewModel.shared
    @State private var lastSeenArticleID: String? = nil
    @State private var previousQuery: String? = nil

    var body: some View {
        PremiumNewsSection(viewModel: vm, lastSeenArticleID: $lastSeenArticleID)
            .onAppear {
                // Defer state modifications to avoid "Modifying state during view update"
                DispatchQueue.main.async {
                    previousQuery = vm.queryOverride
                    vm.queryOverride = "\(symbol) crypto"
                    vm.selectedSources = []
                    vm.loadAllNews(force: true)
                }
            }
            .onDisappear {
                vm.queryOverride = previousQuery
            }
    }
}
