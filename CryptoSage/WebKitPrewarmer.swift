import Foundation
import WebKit
import SwiftUI

// WebKit prewarmer to hide first-run GPU/WebContent/Networking process startup cost.
// It uses the same WKProcessPool as TradingViewChartWebView so the warmed processes
// are reused when the TradingView chart mounts.
final class WebKitPrewarmer {
    static let shared = WebKitPrewarmer()

    private var webView: WKWebView?
    private var warmed = false

    @MainActor
    func warmUp() {
        guard !warmed else { return }
        warmed = true

        let config = WKWebViewConfiguration()
        // Reuse TradingView's shared process pool so this warm-up benefits that WebView.
        config.processPool = TradingViewChartWebView.sharedPool
        let userContent = WKUserContentController()
        config.userContentController = userContent

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.isScrollEnabled = false
        wv.isHidden = true // keep it invisible

        // Minimal HTML that preconnects to TradingView hosts; baseURL pins the process to that domain.
        let html = """
        <!DOCTYPE html>
        <html>
          <head>
            <meta name=\"color-scheme\" content=\"dark\">
            <link rel=\"preconnect\" href=\"https://s3.tradingview.com\" crossorigin>
            <link rel=\"dns-prefetch\" href=\"https://s3.tradingview.com\">
            <link rel=\"preconnect\" href=\"https://widget.tradingview.com\" crossorigin>
            <link rel=\"dns-prefetch\" href=\"https://widget.tradingview.com\">
            <style>html,body{background:transparent;margin:0;padding:0}</style>
          </head>
          <body></body>
        </html>
        """
        wv.loadHTMLString(html, baseURL: URL(string: "https://s3.tradingview.com"))

        // Keep a strong reference so processes stay warm for a while.
        self.webView = wv
    }
}
