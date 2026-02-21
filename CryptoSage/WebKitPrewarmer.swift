import Foundation
import WebKit
import SwiftUI

// WebKit prewarmer to hide first-run GPU/WebContent/Networking process startup cost.
// WebKit automatically manages process pooling in iOS 14+.
// CRASH FIX v3: Simplified non-recursive implementation to avoid stack overflow
// - Removed recursive calls that caused EXC_BAD_ACCESS (code=2)
// - Uses simple timer-based polling instead of recursive Task spawning
// - Safer scroll state checks with fallback defaults
final class WebKitPrewarmer {
    static let shared = WebKitPrewarmer()

    private var webView: WKWebView?
    private var warmed = false
    private var warmingInProgress = false

    /// Call this when user is about to navigate to Trade tab
    /// Much more responsive than warming on app launch
    @MainActor
    func warmUpIfNeeded() {
        guard !warmed && !warmingInProgress else { return }
        warmUp()
    }
    
    @MainActor
    func warmUp() {
        guard !warmed else { return }
        guard !warmingInProgress else { return }
        warmingInProgress = true
        warmed = true
        
        // CRASH FIX v3: Simple delayed execution without recursive scroll checks
        // The scroll state checks were causing stack overflow - just use a fixed delay
        Task { @MainActor in
            // Wait for app to settle (500ms is enough for most scenarios)
            try? await Task.sleep(nanoseconds: 500_000_000)
            self.performWarmUp()
        }
    }
    
    @MainActor
    private func performWarmUp() {
        // Create configuration on main thread (required by iOS 17+)
        let config = WKWebViewConfiguration()
        let userContent = WKUserContentController()
        config.userContentController = userContent
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        
        // PERFORMANCE FIX: Suppress media loading to reduce process startup overhead
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.allowsInlineMediaPlayback = false
        
        // PERFORMANCE FIX: Additional optimizations
        config.suppressesIncrementalRendering = true  // Prevent partial renders

        // PERFORMANCE: Create WebView with minimal configuration first
        // This triggers WebKit process creation (unavoidable main thread work)
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.isScrollEnabled = false
        wv.isHidden = true
        
        // Keep reference immediately so processes start warming
        self.webView = wv
        self.warmingInProgress = false

        // CRASH FIX v3: Simple delayed HTML loading without recursive checks
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000) // 800ms
            self.loadMinimalHTML(into: wv)
        }
    }
    
    /// Load minimal HTML to warm network stack
    @MainActor
    private func loadMinimalHTML(into webView: WKWebView) {
        // Minimal HTML - just DNS prefetch and preconnect, no actual resource loading
        // This is enough to warm the network stack and TLS connections without heavy overhead
        let html = """
        <!DOCTYPE html>
        <html>
          <head>
            <meta name="color-scheme" content="dark">
            <link rel="dns-prefetch" href="https://s3.tradingview.com">
            <link rel="dns-prefetch" href="https://www.tradingview.com">
            <link rel="preconnect" href="https://s3.tradingview.com" crossorigin>
            <link rel="preconnect" href="https://www.tradingview.com" crossorigin>
            <style>html,body{background:#0e0e0e;margin:0;padding:0}</style>
          </head>
          <body></body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
        
        // PERFORMANCE FIX v16: Release the prewarmer WebView after warming is complete
        // Keeping it in memory causes excessive "Message send exceeds rate-limit" errors
        // from WebKit's internal diagnostics during scroll
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000) // Wait 3 seconds for DNS prefetch
            self.release()
        }
    }
    
    /// Release the prewarmed WebView to free memory
    @MainActor
    func release() {
        webView?.stopLoading()
        webView = nil
        warmed = false
        warmingInProgress = false
    }
}
