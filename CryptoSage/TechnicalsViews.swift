// TechnicalsViews.swift
// Reusable gauge wrapper + TradingView Technicals detail

import SwiftUI
import WebKit

// MARK: - Verdict & Summary
public enum TechnicalVerdict: String, CaseIterable, Codable {
    case strongSell = "Strong Sell"
    case sell       = "Sell"
    case neutral    = "Neutral"
    case buy        = "Buy"
    case strongBuy  = "Strong Buy"

    var displayName: String { rawValue }

    // Map to the sentiment classification strings used by ImprovedHalfCircleGauge colors
    var classificationKey: String {
        switch self {
        case .strongSell: return "extreme fear"
        case .sell:       return "fear"
        case .neutral:    return "neutral"
        case .buy:        return "greed"
        case .strongBuy:  return "extreme greed"
        }
    }

    var color: Color {
        switch self {
        case .strongSell: return .red
        case .sell:       return .orange
        case .neutral:    return .yellow
        case .buy:        return .green
        case .strongBuy:  return .mint
        }
    }
}

public struct TechnicalsSummary: Codable, Equatable {
    // score01 in 0...1 for needle position (0 = strong sell, 1 = strong buy)
    public let score01: Double
    public let verdict: TechnicalVerdict

    public init(score01: Double, verdict: TechnicalVerdict) {
        self.score01 = max(0, min(1, score01))
        self.verdict = verdict
    }
}

// MARK: - Compact Gauge View (reuses ImprovedHalfCircleGauge)
public struct TechnicalsGaugeView: View {
    public let summary: TechnicalsSummary
    public var timeframeLabel: String? = nil
    public var lineWidth: CGFloat = 10

    public init(summary: TechnicalsSummary, timeframeLabel: String? = nil, lineWidth: CGFloat = 10) {
        self.summary = summary
        self.timeframeLabel = timeframeLabel
        self.lineWidth = lineWidth
    }

    public var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                // Use the same half-circle gauge used by Market Sentiment, but drive it with technicals
                ImprovedHalfCircleGauge(
                    value: summary.score01 * 100,
                    classification: summary.verdict.classificationKey,
                    lineWidth: lineWidth
                )
                .frame(width: geo.size.width, height: geo.size.height)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Technicals summary: \(summary.verdict.displayName)")
            }
            .frame(height: 160)

            // Verdict line
            HStack(spacing: 6) {
                if let tf = timeframeLabel, !tf.isEmpty {
                    Text(tf)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.trailing, 4)
                }
                Text(summary.verdict.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(summary.verdict.color)
            }
        }
    }
}

// MARK: - TradingView Technicals (Detail)
struct TradingViewTechnicalsWebView: UIViewRepresentable {
    let symbol: String   // e.g. "BINANCE:BTCUSDT"
    let theme: String    // "Dark" or "Light"
    let initialInterval: String = "1D" // let widget show its own tabs; default to 1D

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        let web = WKWebView(frame: .zero, configuration: cfg)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.allowsLinkPreview = false
        web.clipsToBounds = true
        loadHTML(into: web)
        return web
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        // Reload only if theme or symbol changed (simple approach for now)
        // In this minimal implementation we just rebuild the HTML to ensure correctness
        webView.stopLoading()
        loadHTML(into: webView)
    }

    private func loadHTML(into webView: WKWebView) {
        let themeKey = (theme.lowercased().contains("dark")) ? "dark" : "light"
        let html = """
        <!DOCTYPE html>
        <html>
          <head>
            <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
            <style>
              html, body { margin: 0; padding: 0; height: 100%; background: transparent; }
              .tradingview-widget-container { position: absolute; inset: 0; }
            </style>
          </head>
          <body>
            <div class=\"tradingview-widget-container\">
              <div id=\"tv-tech\"></div>
            </div>
            <script type=\"text/javascript\" src=\"https://s3.tradingview.com/external-embedding/embed-widget-technical-analysis.js\" async>
            {
              \"interval\": \"\(initialInterval)\",
              \"width\": \"100%\",
              \"height\": \"100%\",
              \"isTransparent\": true,
              \"symbol\": \"\(symbol)\",
              \"showIntervalTabs\": true,
              \"locale\": \"en\",
              \"colorTheme\": \"\(themeKey)\"
            }
            </script>
          </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://s3.tradingview.com"))
    }
}

public struct TechnicalsDetailView: View {
    let symbol: String
    let theme: String // "Dark" or "Light"

    public init(symbol: String, theme: String) {
        self.symbol = symbol
        self.theme = theme
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TradingViewTechnicalsWebView(symbol: symbol, theme: theme)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Technicals")
        .navigationBarTitleDisplayMode(.inline)
    }
}
