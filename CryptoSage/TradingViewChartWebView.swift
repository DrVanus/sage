import SwiftUI
import WebKit
import Foundation

// MARK: - ChartInterval → TradingView mapping
extension ChartInterval {
    /// Convert shared ChartInterval into TradingView interval string
    var tvValue: String {
        switch self {
        case .oneMin:     return "1"
        case .fiveMin:    return "5"
        case .fifteenMin: return "15"
        case .thirtyMin:  return "30"
        case .oneHour:    return "60"
        case .fourHour:   return "240"
        case .oneDay:     return "D"
        case .oneWeek:    return "W"
        case .oneMonth:   return "M"
        case .threeMonth: return "3M"
        case .oneYear:    return "12M"
        case .threeYear:  return "3Y"
        case .all:        return "ALL"
        case .live:       return "1"
        }
    }
}

// MARK: - Quick indicator types for TradingView
enum IndicatorType: Hashable, CaseIterable {
    case volume, sma, ema, bb, rsi, macd, stoch, vwap, ichimoku, atr, obv, mfi
    var label: String {
        switch self {
        case .volume: return "Volume"
        case .sma: return "SMA"
        case .ema: return "EMA"
        case .bb: return "BB"
        case .rsi: return "RSI"
        case .macd: return "MACD"
        case .stoch: return "Stochastic"
        case .vwap: return "VWAP"
        case .ichimoku: return "Ichimoku"
        case .atr: return "ATR"
        case .obv: return "OBV"
        case .mfi: return "MFI"
        }
    }
    var systemImage: String {
        switch self {
        case .volume: return "chart.bar"
        case .sma: return "chart.line.uptrend.xyaxis"
        case .ema: return "chart.line.flattrend.xyaxis"
        case .bb: return "curlybraces"
        case .rsi: return "waveform.path.ecg"
        case .macd: return "point.3.connected.trianglepath.dotted"
        case .stoch: return "aqi.medium"
        case .vwap: return "chart.xyaxis.line"
        case .ichimoku: return "cloud"
        case .atr: return "ruler"
        case .obv: return "chart.pie"
        case .mfi: return "dollarsign.circle"
        }
    }
}

// MARK: - TradingViewChartWebView (WKWebView wrapper)
struct TradingViewChartWebView: UIViewRepresentable {
    let symbol: String
    let interval: String
    let theme: String
    let studies: [String]
    let altSymbols: [String]
    var isReady: Binding<Bool>? = nil
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.clipsToBounds = true
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
        DispatchQueue.main.async { isReady?.wrappedValue = false }
        loadBaseHTML(into: webView)
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        let c = context.coordinator
        let key = studies.joined(separator: ",")
        let altKey = altSymbols.joined(separator: ",")
        // Cache latest desired config on coordinator
        c.lastSymbol = symbol; c.lastInterval = interval; c.lastTheme = theme; c.lastStudiesKey = key; c.lastAltSymbolsKey = altKey
        // If page finished loading, re-render widget via JS without reloading the WKWebView
        if c.pageLoaded {
            let js = Coordinator.buildRenderJS(symbol: symbol, interval: interval, theme: theme, studies: studies, altSymbols: altSymbols)
            uiView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        let c = Coordinator(ready: isReady)
        c.lastSymbol = symbol
        c.lastInterval = interval
        c.lastTheme = theme
        c.lastStudiesKey = studies.joined(separator: ",")
        c.lastAltSymbolsKey = altSymbols.joined(separator: ",")
        return c
    }
    
    private func loadBaseHTML(into webView: WKWebView) {
        let html = """
        <!DOCTYPE html>
        <html>
          <head>
            <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
            <link rel=\"preconnect\" href=\"https://s3.tradingview.com\" crossorigin>
            <style>
              html, body { margin: 0; padding: 0; height: 100%; background: transparent; }
              #tv_chart_container { position: absolute; top:0; left:0; right:0; bottom:0; min-height: 120px; }
              .tv-loading-screen, .chart-container .loading-indicator { display: none !important; opacity: 0 !important; }
              #tv_chart_container, .tv-chart-view, .chart-container { opacity: 1 !important; }
            </style>
            <script>
              // Persistent widget + config tracking
              window.tvWidget = null;
              window._tvPendingCfg = null;
              window._tvTheme = null;
              window._tvStudiesKey = null;
              window._tvLoaded = false;

              window._tvLastCfg = null;
              window._tvEnsureTimer = null;
              window._tvAltSymbols = [];
              window._tvAltIndex = 0;

              function tryNextAlt() {
                try {
                  if (!window._tvAltSymbols || window._tvAltSymbols.length === 0) { return; }
                  window._tvAltIndex = (window._tvAltIndex + 1) % window._tvAltSymbols.length;
                  var alt = window._tvAltSymbols[window._tvAltIndex];
                  if (window.tvWidget && window.tvWidget.chart) {
                    window.tvWidget.chart().setSymbol(alt, (window._tvLastCfg && window._tvLastCfg.interval) || '60');
                  }
                } catch(e) {}
              }

              function ensureRendered() {
                try {
                  var container = document.getElementById('tv_chart_container');
                  if (container) { container.style.opacity = '1'; }
                  if (!window.TradingView) { return; }
                  if (!window.tvWidget) {
                    if (window._tvLastCfg) { _doRender(window._tvLastCfg); }
                    return;
                  }
                  var ch = (window.tvWidget.chart && window.tvWidget.chart()) || null;
                  if (!ch || (typeof ch.getVisibleRange !== 'function')) {
                    if (window._tvLastCfg) { _doRender(window._tvLastCfg); }
                    return;
                  }
                  try {
                    var cfg = window._tvLastCfg || { symbol: 'BTCUSDT', interval: '60', theme: 'Dark', studies: [] };
                    ch.setSymbol(cfg.symbol, cfg.interval);
                  } catch(e) {}
                  try { dedupeVolumeStudies(); } catch(e) {}
                } catch(e) {}
              }

              function startEnsureTimer() {
                try {
                  if (window._tvEnsureTimer) { clearInterval(window._tvEnsureTimer); }
                  var ticks = 0;
                  window._tvEnsureTimer = setInterval(function(){
                    ticks++;
                    try {
                      ensureRendered(); dedupeVolumeStudies();
                      // Rotate fallback symbols if chart still not interactive after a few ticks
                      if (window.tvWidget && window.tvWidget.chart) {
                        var ch = window.tvWidget.chart();
                        var ok = false;
                        try { var vr = ch.getVisibleRange(); ok = !!vr; } catch(e) { ok = false; }
                        if (!ok && (ticks === 6 || ticks === 10)) { tryNextAlt(); }
                      }
                    } catch(e) {}
                    if (ticks >= 18) { clearInterval(window._tvEnsureTimer); window._tvEnsureTimer = null; }
                  }, 500);
                } catch(e) {}
              }

              function dedupeVolumeStudies() {
                try {
                  if (!window.tvWidget || !window.tvWidget.chart) { return; }
                  var chart = window.tvWidget.chart();
                  var studies = chart.getAllStudies ? chart.getAllStudies() : [];
                  var volStudyIds = [];
                  for (var i = 0; i < studies.length; i++) {
                    var s = studies[i];
                    var name = (s && s.name) ? String(s.name) : "";
                    if (name.toLowerCase().indexOf('volume') !== -1) { volStudyIds.push(s.id); }
                  }
                  for (var j = 1; j < volStudyIds.length; j++) {
                    try { chart.removeEntity(volStudyIds[j]); } catch (e) {}
                  }
                } catch (e) { /* noop */ }
              }

              function _doRender(cfg) {
                try {
                  window._tvLastCfg = cfg;
                  var studiesKey = (cfg.studies || []).join(',');
                  var needRecreate = (!window.tvWidget) || (window._tvTheme !== cfg.theme) || (window._tvStudiesKey !== studiesKey);
                  if (!needRecreate) {
                    try {
                      window.tvWidget.chart().setSymbol(cfg.symbol, cfg.interval);
                      setTimeout(function(){ try { dedupeVolumeStudies(); } catch(e) {} }, 120);
                    } catch (e) { needRecreate = true; }
                  }

                  if (needRecreate) {
                    if (window.tvWidget && window.tvWidget.remove) { try { window.tvWidget.remove(); } catch(e) {} }
                    window._tvTheme = cfg.theme;
                    window._tvStudiesKey = studiesKey;
                    window.tvWidget = new TradingView.widget({
                      container_id: 'tv_chart_container',
                      symbol: cfg.symbol,
                      interval: cfg.interval,
                      timezone: 'Etc/UTC',
                      theme: cfg.theme,
                      style: '1',
                      locale: 'en',
                      withdateranges: false,
                      hide_side_toolbar: true,
                      hide_top_toolbar: true,
                      hide_bottom_toolbar: true,
                      hide_legend: true,
                      allow_symbol_change: false,
                      autosize: true,
                      studies: cfg.studies,
                      studies_overrides: {},
                      loading_screen: { backgroundColor: 'rgba(0,0,0,0)', foregroundColor: 'rgba(0,0,0,0)' },
                      overrides: {
                        'paneProperties.background': 'rgba(0,0,0,0)',
                        'layout.backgroundColor': 'rgba(0,0,0,0)',
                        'scalesProperties.textColor': 'rgba(255,255,255,0.65)',
                        'scalesProperties.showLeftScale': false
                      }
                    });
                    document.getElementById('tv_chart_container').style.opacity = '1';
                    startEnsureTimer();
                    window.tvWidget.onChartReady(function() {
                      try { dedupeVolumeStudies(); } catch(e) {}
                      setTimeout(function(){ try { dedupeVolumeStudies(); } catch(e) {} }, 200);
                      startEnsureTimer();
                    });
                  }
                } catch (e) {
                  setTimeout(function(){ window.renderTV(cfg.symbol, cfg.interval, cfg.theme, cfg.studies, window._tvAltSymbols || []); }, 150);
                }
              }

              window.renderTV = function(symbol, interval, theme, studies, alts) {
                var cfg = { symbol: symbol, interval: interval, theme: theme, studies: studies };
                window._tvAltSymbols = Array.isArray(alts) ? alts : [];
                window._tvAltIndex = 0;
                if (!window.TradingView) { window._tvPendingCfg = cfg; return; }
                _doRender(cfg);
              };

              // Resilient tv.js loader with retry + cache-busting + hard timeout fallback
              (function loadTvJs(retry){
                var s = document.createElement('script');
                var base = 'https://s3.tradingview.com/tv.js';
                var url = base + (retry > 0 ? ('?v=' + Date.now()) : '');
                s.src = url;
                s.async = true; s.defer = true; s.crossOrigin = 'anonymous';
                var hardTimeout = setTimeout(function(){
                  if (!window.TradingView) {
                    document.getElementById('tv_chart_container').innerHTML = '<div style="color:yellow;text-align:center;margin-top:40px;font-family:-apple-system,Helvetica,Arial;">TradingView unavailable. Tap TradingView again to retry.</div>';
                  }
                }, 6000);
                s.onload = function(){
                  clearTimeout(hardTimeout);
                  window._tvLoaded = true;
                  if (window._tvPendingCfg) { var cfg = window._tvPendingCfg; window._tvPendingCfg = null; _doRender(cfg); setTimeout(function(){ try { dedupeVolumeStudies(); } catch(e) {} }, 150); startEnsureTimer(); }
                };
                s.onerror = function(){
                  clearTimeout(hardTimeout);
                  if (retry < 2) {
                    setTimeout(function(){ loadTvJs(retry + 1); }, 500);
                  } else {
                    document.getElementById('tv_chart_container').innerHTML = '<div style="color:yellow;text-align:center;margin-top:40px;font-family:-apple-system,Helvetica,Arial;">TradingView unavailable in your region or network.</div>';
                  }
                };
                document.head.appendChild(s);
              })(0);
            </script>
          </head>
          <body>
            <div id="tv_chart_container"></div>
          </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://s3.tradingview.com"))
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var ready: Binding<Bool>?
        init(ready: Binding<Bool>?) { self.ready = ready }
        
        var lastSymbol: String = ""
        var lastInterval: String = ""
        var lastTheme: String = ""
        var lastStudiesKey: String = ""
        var lastAltSymbolsKey: String = ""
        var pageLoaded: Bool = false
        
        func webView(_ webView: WKWebView,
                     didFinish navigation: WKNavigation!) {
            pageLoaded = true
            let alts = lastAltSymbolsKey.split(separator: ",").map(String.init)
            let js = Coordinator.buildRenderJS(symbol: lastSymbol, interval: lastInterval, theme: lastTheme, studies: lastStudiesKey.split(separator: ",").map(String.init), altSymbols: alts)
            webView.evaluateJavaScript(js, completionHandler: nil)
            let hideLoaderJS = """
            (function(){
              var els = document.querySelectorAll('.tv-loading-screen, .chart-container .loading-indicator');
              for (var i=0;i<els.length;i++){ els[i].style.display='none'; }
            })();
            """
            webView.evaluateJavaScript(hideLoaderJS, completionHandler: nil)
            DispatchQueue.main.async { self.ready?.wrappedValue = true }
            print("TradingView web content finished loading.")
        }
        
        func webView(_ webView: WKWebView,
                     didFail navigation: WKNavigation!,
                     withError error: Error) {
            fallbackMessage(in: webView)
            ready?.wrappedValue = true
        }
        
        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            // -999 are common cancellation errors when subresources race; ignore them.
            let nsErr = error as NSError
            if nsErr.domain == NSURLErrorDomain && nsErr.code == NSURLErrorCancelled {
                let hideLoaderJS = """
                (function(){
                  var els = document.querySelectorAll('.tv-loading-screen, .chart-container .loading-indicator');
                  for (var i=0;i<els.length;i++){ els[i].style.display='none'; }
                })();
                """
                webView.evaluateJavaScript(hideLoaderJS, completionHandler: nil)
                DispatchQueue.main.async { self.ready?.wrappedValue = true }
                return
            }
            // For real failures, show a friendly message but keep background transparent
            let fallbackHTML = """
            <html><body style=\"background:transparent;color:yellow;text-align:center;padding-top:40px;\">
            <h3>TradingView is blocked in your region or unavailable.</h3>
            <p>Try a VPN or different region.</p>
            </body></html>
            """
            webView.loadHTMLString(fallbackHTML, baseURL: nil)
            DispatchQueue.main.async { self.ready?.wrappedValue = true }
        }
        
        private func fallbackMessage(in webView: WKWebView) {
            let fallbackHTML = """
            <html><body style=\"background:transparent;color:yellow;text-align:center;padding-top:40px;\">
            <h3>TradingView is blocked in your region or unavailable.</h3>
            <p>Try a VPN or different region.</p>
            </body></html>
            """
            webView.loadHTMLString(fallbackHTML, baseURL: nil)
        }
        
        static func buildRenderJS(symbol: String, interval: String, theme: String, studies: [String], altSymbols: [String]) -> String {
            let studiesJS = studies.map { "'\($0)'" }.joined(separator: ",")
            let altsJS = altSymbols.map { "'\($0)'" }.joined(separator: ",")
            return "window.renderTV('" + symbol + "','" + interval + "','" + theme + "',[" + studiesJS + "],[" + altsJS + "]);"
        }
    }
}
