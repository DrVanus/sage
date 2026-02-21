import SwiftUI
import WebKit
import Foundation

// MARK: - ChartInterval → TradingView mapping
extension ChartInterval {
    /// Convert shared ChartInterval into TradingView interval string
    /// TradingView only supports: 1, 3, 5, 15, 30, 45, 60, 120, 180, 240, D, W, M
    /// Longer timeframes (3M, 6M, 1Y, 3Y, All) use the closest valid resolution
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
        case .threeMonth: return "D"     // Use daily candles (TradingView doesn't support "3M")
        case .sixMonth:   return "D"     // Use daily candles (TradingView doesn't support "6M")
        case .oneYear:    return "W"     // Use weekly candles (TradingView doesn't support "12M")
        case .threeYear:  return "W"     // Weekly candles for 3-year view
        case .all:        return "M"     // Monthly candles for all-time view
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
    // Note: sharedPool removed - processPool was deprecated in iOS 14, WebKit now manages process pooling automatically
    
    let symbol: String
    let interval: String
    let theme: String
    let studies: [String]
    let altSymbols: [String]
    let interactive: Bool
    var isReady: Binding<Bool>? = nil
    
    func makeUIView(context: Context) -> WKWebView {
        // PERFORMANCE FIX: Trigger prewarmer if not already done
        // This helps reduce WebKit process startup delays
        WebKitPrewarmer.shared.warmUpIfNeeded()
        
        // Build a configuration that forwards JS console to Swift for debugging
        let config = WKWebViewConfiguration()
        // Note: processPool was deprecated in iOS 14 - WebKit now manages process pooling automatically
        let userContent = WKUserContentController()
        let bridgeJS = """
        (function(){
          function f(type, payload){ try { window.webkit.messageHandlers.tvlog.postMessage({ type: type, payload: payload }); } catch(e){} }

          // Heuristic suppression for chatty/benign warnings from embedded widgets
          function _joinArgs(args){ try { return Array.prototype.map.call(args, function(a){ return (typeof a === 'string') ? a : String(a); }).join(' '); } catch(e){ return ''; } }
          function _shouldSuppress(kind, args){
            try {
              if (kind === 'log') return false; // never suppress normal logs here
              var msg = String(_joinArgs(args) || '');
              // Common benign messages we want to drop from Xcode logs
              var patterns = [
                /does not exist/i,
                /unknown property/i,
                /unknown parameter/i,
                /is deprecated/i,
                /expected .* but got/i,
                /show_last_value/i,
                /has no plot/i,
                /has no input/i,
                /StudyPropertiesOverrider/i
              ];
              for (var i=0;i<patterns.length;i++){ if (patterns[i].test(msg)) return true; }
              return false;
            } catch(e){ return false; }
          }

          ['log','warn','error'].forEach(function(k){
            var old = console[k];
            console[k] = function(){
              var args = Array.from(arguments);
              var suppress = _shouldSuppress(k, args);
              if (!suppress) { try { f(k, args); } catch(_){} }
              // Only call the original console for non-suppressed messages so WebKit doesn't echo them
              if (!suppress && old) try { old.apply(console, arguments); } catch(_){ }
            };
          });

          window.addEventListener('error', function(e){
            try {
              var msg = String(e && e.message || '');
              if (!/does not exist|unknown property|unknown parameter|is deprecated|show_last_value/i.test(msg)) {
                f('window.onerror', { message: msg, src: String(e && e.filename || ''), line: e && e.lineno || 0, col: e && e.colno || 0 });
              }
            } catch(_){ }
          });

          // Haptics bridge to native with rate limiting to prevent IPC queue overflow
          // CRASH FIX: Without throttling, rapid pointer moves flood WebKit->Native IPC
          // causing "Message send exceeds rate-limit threshold" and eventual crash
          (function(){
            var lastTickAt = 0;
            var lastMoveAt = 0;
            var tickThrottle = 25;  // Max 40 tick messages per second (25ms between)
            var moveThrottle = 16;  // Max 60 pointermove haptics per second (16ms between)
            window.postHaptic = function(type, payload){
              try {
                var now = Date.now();
                // Always allow begin/end/major events through immediately
                if (type === 'begin' || type === 'end' || type === 'major' || type === 'success' || type === 'warning' || type === 'error') {
                  lastTickAt = 0; // Reset throttle on session start/end
                  lastMoveAt = 0;
                  window.webkit.messageHandlers.haptics.postMessage({ type: String(type||''), payload: payload||null });
                  return;
                }
                // Throttle tick events (crosshair moves)
                if (type === 'tick') {
                  if (now - lastTickAt < tickThrottle) return; // Drop if too soon
                  lastTickAt = now;
                }
                // Throttle grid bumps
                if (type === 'grid') {
                  if (now - lastMoveAt < moveThrottle) return;
                  lastMoveAt = now;
                }
                window.webkit.messageHandlers.haptics.postMessage({ type: String(type||''), payload: payload||null });
              } catch(e){}
            };
          })();
        })();
        """
        let script = WKUserScript(source: bridgeJS, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        userContent.addUserScript(script)
        userContent.add(context.coordinator, name: "tvlog")
        userContent.add(context.coordinator, name: "haptics")
        config.userContentController = userContent

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.clipsToBounds = true
        webView.allowsLinkPreview = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        // Use dynamic iOS version so TradingView doesn't serve outdated content for a stale UA
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let osVer = "\(v.majorVersion)_\(v.minorVersion)"
        let safariVer = "\(v.majorVersion).0"
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS \(osVer) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(safariVer) Mobile/15E148 Safari/604.1"
        DispatchQueue.main.async { isReady?.wrappedValue = false }
        loadBaseHTML(into: webView)
        
        // LOADING TIMEOUT: If TradingView fails to load within 15 seconds (CDN down,
        // network issues, region block), show a friendly error instead of an empty chart.
        context.coordinator.loadingTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { [weak webView, weak coordinator = context.coordinator] _ in
            Task { @MainActor in
                guard let wv = webView, coordinator?.pageLoaded != true else { return }
                let timeoutHTML = """
            <html><body style="background:transparent;color:#FFD700;text-align:center;padding-top:40px;font-family:-apple-system,sans-serif;">
            <h3>TradingView chart could not load</h3>
            <p style="color:#888;">Check your internet connection or try again later.</p>
            </body></html>
            """
                wv.loadHTMLString(timeoutHTML, baseURL: nil)
                coordinator?.ready?.wrappedValue = true
            }
        }
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        let c = context.coordinator
        c.lastSymbol = symbol; c.lastInterval = interval; c.lastTheme = theme; c.lastStudies = studies; c.lastInteractive = interactive
        c.lastAltSymbols = altSymbols
        // If page finished loading, apply changes
        if c.pageLoaded {
            let symbolChanged = (symbol != c.appliedSymbol)
            let intervalChanged = (interval != c.appliedInterval)
            let themeChanged = (theme != c.appliedTheme)
            let studiesChanged = (studies != c.appliedStudies)
            let unchangedCore = !symbolChanged && !intervalChanged && !themeChanged && !studiesChanged
            
            if !unchangedCore {
                #if DEBUG
                if intervalChanged {
                    print("[TradingViewChart] Interval changed: \(c.appliedInterval) -> \(interval)")
                }
                #endif
                let js = Coordinator.buildRenderJS(symbol: symbol, interval: interval, theme: theme, studies: studies, altSymbols: altSymbols)
                uiView.evaluateJavaScript(js, completionHandler: nil)
                c.appliedSymbol = symbol; c.appliedInterval = interval; c.appliedTheme = theme; c.appliedStudies = studies
                c.appliedAltSymbols = altSymbols
            }
            if c.appliedInteractive != interactive {
                let js = Coordinator.buildSetInteractivityJS(enabled: interactive)
                uiView.evaluateJavaScript(js, completionHandler: nil)
                c.appliedInteractive = interactive
            }
        }
    }
    
    // MEMORY LEAK FIX: Remove script message handler references when the view is dismantled.
    // WKUserContentController holds a strong reference to its message handlers, which creates
    // a retain cycle (Controller -> Coordinator -> ready binding). Without cleanup, neither
    // the Coordinator nor the WebView's configuration can be deallocated.
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.configuration.userContentController.removeAllScriptMessageHandlers()
        uiView.stopLoading()
        coordinator.loadingTimer?.invalidate()
        coordinator.loadingTimer = nil
    }
    
    func makeCoordinator() -> Coordinator {
        let c = Coordinator(ready: isReady)
        c.lastSymbol = symbol
        c.lastInterval = interval
        c.lastTheme = theme
        c.lastStudies = studies
        c.lastInteractive = interactive
        c.lastAltSymbols = altSymbols
        return c
    }
    
    private func loadBaseHTML(into webView: WKWebView) {
        let html = """
        <!DOCTYPE html>
        <html>
          <head>
            <meta name=\"viewport\" content=\"width=device-width, initial-scale=1.0\">
            <link rel=\"preconnect\" href=\"https://s3.tradingview.com\" crossorigin>
            <link rel=\"dns-prefetch\" href=\"https://s3.tradingview.com\">
            <link rel=\"preconnect\" href=\"https://www.tradingview.com\" crossorigin>
            <link rel=\"dns-prefetch\" href=\"https://www.tradingview.com\">
            <link rel=\"preconnect\" href=\"https://widget.tradingview.com\" crossorigin>
            <link rel=\"dns-prefetch\" href=\"https://widget.tradingview.com\">
            <link rel=\"preload\" as=\"script\" href=\"https://s3.tradingview.com/tv.js\" fetchpriority=\"high\">
            <style>
              html, body { margin: 0; padding: 0; height: 100%; width: 100%; background: #0e0e0e; overflow: hidden; }
              #tv_chart_container { 
                position: absolute; 
                inset: 0; 
                min-height: 120px; 
                background: #0e0e0e; 
                pointer-events: none;
                /* Smooth transition for loading states */
                transition: opacity 0.15s ease-out;
              }
              /* Hide TradingView's loading spinner to prevent flash during recreation */
              .tv-loading-screen,
              .chart-container .loading-indicator,
              .chart-markup-table .loading-indicator {
                background: transparent !important;
                opacity: 0 !important;
              }
            </style>
            <script>
              // Single, stable widget lifecycle
              window.tvWidget = null;
              window._pendingCfg = null;
              window._currentTheme = null;
              window._currentStudiesKey = null;
              window._currentSymbol = null;
              window._currentInterval = null;
              window._currentWantsVolume = null; // Track volume preference for widget recreation
              window._altSymbols = [];
              window._altIndex = 0;
              window._fallbackTimer = null;
              window._appliedStudyIds = []; // Track currently applied study entity IDs for dynamic removal
              window._lastRenderAt = 0; // Debounce timestamp
              window._pendingRender = null; // Pending render timeout

              // CRITICAL: Deterministic JSON stringify to prevent infinite reload loops
              // Standard JSON.stringify can produce different key orders on each call
              function stableStringify(obj) {
                if (obj === null || obj === undefined) return '';
                if (typeof obj !== 'object') return String(obj);
                if (Array.isArray(obj)) {
                  return '[' + obj.map(function(v) { return stableStringify(v); }).join(',') + ']';
                }
                // Sort keys for deterministic output
                var keys = Object.keys(obj).sort();
                var parts = [];
                for (var i = 0; i < keys.length; i++) {
                  var k = keys[i];
                  var v = obj[k];
                  if (v !== undefined) {
                    parts.push('"' + k + '":' + (typeof v === 'object' ? stableStringify(v) : JSON.stringify(v)));
                  }
                }
                return '{' + parts.join(',') + '}';
              }

              // Parse study descriptor: string, object, or JSON string to {id, inputs}
              function parseStudyDescriptor(s) {
                try {
                  if (typeof s === 'string') {
                    s = s.trim();
                    if (s.startsWith('{')) {
                      var obj = JSON.parse(s);
                      if (obj && typeof obj === 'object' && typeof obj.id === 'string') {
                        return { id: obj.id, inputs: obj.inputs && typeof obj.inputs === 'object' ? obj.inputs : null };
                      }
                      return null;
                    } else {
                      // Plain string id
                      return { id: s, inputs: null };
                    }
                  } else if (typeof s === 'object' && s !== null) {
                    if (typeof s.id === 'string') {
                      return { id: s.id, inputs: s.inputs && typeof s.inputs === 'object' ? s.inputs : null };
                    }
                    return null;
                  }
                  return null;
                } catch (e) {
                  return null;
                }
              }

              // Convert our study descriptors to TradingView widget constructor format
              // Returns ALL studies (including overlay) for direct widget initialization
              function buildWidgetStudies(studyObjs) {
                var result = [];
                for (var i = 0; i < studyObjs.length; i++) {
                  var obj = studyObjs[i];
                  // Skip Volume - handled via disabled_features
                  if (obj.id.toLowerCase().indexOf('volume@') === 0) continue;
                  
                  // Build study entry for widget constructor
                  var entry = { id: obj.id };
                  if (obj.inputs && Object.keys(obj.inputs).length > 0) {
                    entry.inputs = obj.inputs;
                  }
                  result.push(entry);
                }
                return result;
              }

              // Container is always visible now (dark bg prevents white flash); these are no-ops kept for call-site compatibility
              function hideContainer(){ }
              function showContainer(){ }

              // Toggle pointer interactivity from Swift
              function setTVInteractivity(enabled){
                try {
                  var el = document.getElementById('tv_chart_container');
                  if (el) { el.style.pointerEvents = enabled ? 'auto' : 'none'; }
                } catch(e){}
              }
              window.setTVInteractivity = setTVInteractivity;

              // Install basic pointer listeners on the container to signal haptic session lifecycle
              // NOTE: postHaptic() has built-in throttling to prevent IPC queue overflow
              // This allows these handlers to fire frequently without crashing the app
              function installHapticsHooks(){
                try {
                  var el = document.getElementById('tv_chart_container');
                  if (!el) return;
                  if (el._hapticsInstalled) return; // idempotent
                  el._hapticsInstalled = true;
                  el.addEventListener('pointerdown', function(){ try { if (window.postHaptic) window.postHaptic('begin'); } catch(e){} });
                  ['pointerup','pointercancel','pointerleave'].forEach(function(evt){
                    el.addEventListener(evt, function(){ try { if (window.postHaptic) window.postHaptic('end'); } catch(e){} });
                  });
                  // pointermove fires very frequently - throttled at postHaptic level
                  el.addEventListener('pointermove', function(){ try { if (window.postHaptic) window.postHaptic('tick'); } catch(e){} });
                } catch(e){}
              }

              function tryApplySymbol(targetSymbol, interval, altSymbols){
                try {
                  window._altSymbols = Array.isArray(altSymbols) ? altSymbols.slice() : [String(targetSymbol||'')];
                  if (window._altSymbols.length === 0) { window._altSymbols = [String(targetSymbol||'')]; }
                  window._altIndex = 0;
                  var chart = window.tvWidget && window.tvWidget.chart ? window.tvWidget.chart() : null;
                  if (!chart) { 
                    console.log('[TV] tryApplySymbol: No chart object available');
                    return; 
                  }
                  // one-time subscribe to clear fallback timer when symbol actually changes
                  try {
                    if (!chart._hasSymbolChangedHook) {
                      chart._hasSymbolChangedHook = true;
                      chart.onSymbolChanged().subscribe(null, function(){ try { clearTimeout(window._fallbackTimer); } catch(e){} });
                    }
                  } catch(e){}

                  function applyAt(index){
                    var sym = window._altSymbols[index] || targetSymbol;
                    try {
                      // Get current resolution - TradingView may use resolution() or activeChart().resolution()
                      var currentResolution = null;
                      try {
                        currentResolution = chart.resolution ? chart.resolution() : null;
                      } catch(e) {
                        // Some widget versions use different API
                        try {
                          currentResolution = window.tvWidget.activeChart ? window.tvWidget.activeChart().resolution() : null;
                        } catch(e2) {}
                      }
                      
                      var needResolutionChange = (currentResolution !== interval);
                      console.log('[TV] Resolution change: ' + currentResolution + ' -> ' + interval + ' (needChange: ' + needResolutionChange + ')');
                      
                      if (needResolutionChange) {
                        // setResolution takes (resolution, callback) - change resolution first
                        try {
                          chart.setResolution(interval, function(){
                            console.log('[TV] Resolution changed successfully to: ' + interval);
                            try {
                              // Now change symbol if different
                              var currentSymbol = chart.symbol ? chart.symbol() : null;
                              if (currentSymbol !== sym) {
                                chart.setSymbol(sym, function(){ try { showContainer(); } catch(e){} });
                              } else {
                                try { showContainer(); } catch(e){}
                              }
                            } catch(e){ 
                              console.log('[TV] Error in resolution callback: ' + e);
                              try { showContainer(); } catch(e2){} 
                            }
                          });
                        } catch(resErr) {
                          console.log('[TV] setResolution failed: ' + resErr + ', trying alternative method');
                          // Try alternative: resetData approach for some widget versions
                          try {
                            if (chart.resetData) {
                              chart.resetData();
                            }
                          } catch(e2) {}
                          try { showContainer(); } catch(e){}
                        }
                      } else {
                        // Only symbol change needed
                        var currentSymbol = chart.symbol ? chart.symbol() : null;
                        if (currentSymbol !== sym) {
                          chart.setSymbol(sym, function(){ try { showContainer(); } catch(e){} });
                        } else {
                          try { showContainer(); } catch(e){}
                        }
                      }
                    } catch(e) {
                      console.log('[TV] applyAt error: ' + e);
                      // immediate fallback
                      fallbackTo(index + 1);
                      return;
                    }
                    try { clearTimeout(window._fallbackTimer); } catch(e){}
                    window._fallbackTimer = setTimeout(function(){ fallbackTo(index + 1); }, 1500);
                  }

                  function fallbackTo(nextIndex){
                    try { clearTimeout(window._fallbackTimer); } catch(e){}
                    if (nextIndex < window._altSymbols.length) {
                      window._altIndex = nextIndex;
                      applyAt(nextIndex);
                    } else {
                      // give up; keep last attempt
                      try { showContainer(); } catch(e){}
                    }
                  }

                  applyAt(0);
                } catch(e){ console.log('[TV] tryApplySymbol error: ' + e); }
              }

              function renderTV(symbol, interval, theme, studies, altSymbols) {
                try {
                  showContainer();
                  var cfg = { symbol: String(symbol||'BTCUSDT'), interval: String(interval||'60'), theme: String(theme||'Dark'), studies: Array.isArray(studies) ? studies : [], altSymbols: Array.isArray(altSymbols) ? altSymbols : [] };
                  if (!window.TradingView) { window._pendingCfg = cfg; return; }

                  // De-dupe incoming study strings or objects defensively by id+inputs JSON
                  var seen = {};
                  var studyObjs = [];
                  var wantsVolume = false; // Track if user has Volume enabled in their preferences
                  for (var i=0;i<cfg.studies.length;i++) {
                    var obj = parseStudyDescriptor(cfg.studies[i]);
                    if(!obj) continue;
                    // Check if Volume is in the requested studies
                    if (obj.id.toLowerCase().indexOf('volume@') === 0) {
                      wantsVolume = true;
                    }
                    var key = obj.id + JSON.stringify(obj.inputs||{});
                    if (!seen[key]) {
                      seen[key] = true;
                      studyObjs.push(obj);
                    }
                  }

                  // Build studiesKey from ALL studies including their inputs
                  // CRITICAL: Use stableStringify for deterministic key generation
                  // This prevents infinite reload loops caused by inconsistent JSON key ordering
                  var studiesKey = studyObjs.map(function(o){
                    return o.id + (o.inputs ? stableStringify(o.inputs) : '');
                  }).join('|');
                  
                  // Build studies array for widget constructor
                  var widgetStudies = buildWidgetStudies(studyObjs);
                  
                  // Check what changed
                  var studiesChanged = (window._currentStudiesKey !== studiesKey);
                  var themeChanged = (window._currentTheme !== cfg.theme);
                  var volumeChanged = (window._currentWantsVolume !== wantsVolume);
                  
                  // STABILITY CHECK: Log when studies appear to change (helps debug loops)
                  if (studiesChanged && window._currentStudiesKey) {
                    console.log('[TV] Studies key changed from: ' + (window._currentStudiesKey || '(none)').substring(0, 100));
                    console.log('[TV] Studies key changed to: ' + studiesKey.substring(0, 100));
                  }
                  
                  // Recreate widget when theme, volume, or studies change
                  // This ensures proper initialization of all indicators
                  var needRecreate = (!window.tvWidget) || themeChanged || volumeChanged || studiesChanged;

                  // DEBOUNCE: Only apply to widget recreations, not symbol/interval changes
                  // This prevents infinite loops from cascading state updates while allowing
                  // timeframe switching to work immediately
                  if (needRecreate && window.tvWidget) {
                    var now = Date.now();
                    var timeSinceLastRecreate = now - window._lastRenderAt;
                    if (timeSinceLastRecreate < 300) {
                      // Debounce: schedule a delayed recreation instead
                      if (window._pendingRender) { clearTimeout(window._pendingRender); }
                      window._pendingRender = setTimeout(function() {
                        window._pendingRender = null;
                        renderTV(symbol, interval, theme, studies, altSymbols);
                      }, 300 - timeSinceLastRecreate + 50);
                      return;
                    }
                    window._lastRenderAt = now;
                  }

                  if (needRecreate) {
                    if (window.tvWidget && window.tvWidget.remove) { try { window.tvWidget.remove(); } catch(e) {} }
                    window._currentTheme = cfg.theme;
                    window._currentStudiesKey = studiesKey;
                    window._currentWantsVolume = wantsVolume;
                    
                    // DEFINITIVE FIX: Pass studies directly to widget constructor
                    // This ensures indicators are properly aligned with price data from initialization
                    // Dynamic createStudy after chart load causes alignment issues
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
                      studies: widgetStudies,
                      disabled_features: wantsVolume ? [] : ['create_volume_indicator_by_default'],
                      loading_screen: { backgroundColor: 'rgba(0,0,0,0)', foregroundColor: 'rgba(0,0,0,0)' },
                      overrides: {
                        'paneProperties.background': 'rgba(0,0,0,0)',
                        'paneProperties.backgroundType': 'solid',
                        'layout.backgroundColor': 'rgba(0,0,0,0)',
                        'layout.lineColor': 'rgba(0,0,0,0)',
                        'scalesProperties.textColor': 'rgba(255,255,255,0.65)',
                        'scalesProperties.showLeftScale': false,
                        'scalesProperties.showSeriesLastValue': false,
                        'scalesProperties.showSymbolLabels': false,
                        'mainSeriesProperties.priceLineColor': 'rgba(0,0,0,0)',
                        'mainSeriesProperties.priceLineWidth': 0,
                        'mainSeriesProperties.showPriceLine': false,
                        'paneProperties.rightMargin': 4,
                        'paneProperties.topMargin': 6,
                        'paneProperties.bottomMargin': 6,
                        'paneProperties.vertGridProperties.color': 'rgba(255,255,255,0.08)',
                        'paneProperties.horzGridProperties.color': 'rgba(255,255,255,0.08)',
                        'scalesProperties.lineColor': 'rgba(255,255,255,0.08)',
                        'scalesProperties.showStudyLastValue': false,
                        'timeScale.rightOffset': 0
                      },
                      studies_overrides: {
                        // Volume - subtle bars that don't overpower price action
                        'volume.show_last_value': false,
                        'volume.volume.transparency': 70,
                        'volume.volume ma.show_last_value': false,
                        'volume.volume ma.transparency': 85,
                        
                        // Moving Averages - gold/amber theme colors for better visibility
                        // TradingView uses 'MA.ma.color' format (not 'moving average.plot.color')
                        'moving average.ma.color': '#FFD700',          // Gold for SMA
                        'moving average.ma.linewidth': 2,
                        'moving average.show_last_value': false,
                        'moving average exponential.ma.color': '#FF9500', // Orange for EMA
                        'moving average exponential.ma.linewidth': 2,
                        'moving average exponential.show_last_value': false,
                        
                        // Bollinger Bands - subtle purple bands
                        'bollinger bands.upper.color': '#A78BFA',
                        'bollinger bands.lower.color': '#A78BFA',
                        'bollinger bands.median.color': '#8B5CF6',
                        'bollinger bands.upper.linewidth': 1,
                        'bollinger bands.lower.linewidth': 1,
                        'bollinger bands.median.linewidth': 1,
                        'bollinger bands.fill.transparency': 90,
                        'bollinger bands.show_last_value': false,
                        
                        // RSI - teal/cyan for momentum
                        'relative strength index.plot.color': '#2DD4BF',
                        'relative strength index.plot.linewidth': 2,
                        'relative strength index.hline.color': 'rgba(255,255,255,0.2)',
                        'relative strength index.show_last_value': false,
                        
                        // MACD - classic red/green with gold signal
                        'macd.macd.color': '#22C55E',                  // Green for MACD line
                        'macd.signal.color': '#FFD700',                // Gold for signal line
                        'macd.histogram.color': '#EF4444',             // Red for histogram
                        'macd.macd.linewidth': 2,
                        'macd.signal.linewidth': 2,
                        'macd.show_last_value': false,
                        
                        // Stochastic - teal tones
                        'stochastic.%k.color': '#14B8A6',
                        'stochastic.%d.color': '#FFD700',
                        'stochastic.%k.linewidth': 2,
                        'stochastic.%d.linewidth': 1,
                        'stochastic.hline.color': 'rgba(255,255,255,0.2)',
                        'stochastic.show_last_value': false,
                        
                        // ATR - yellow/amber
                        'average true range.plot.color': '#FBBF24',
                        'average true range.plot.linewidth': 2,
                        'average true range.show_last_value': false,
                        
                        // OBV - cyan
                        'on balance volume.plot.color': '#06B6D4',
                        'on balance volume.plot.linewidth': 2,
                        'on balance volume.show_last_value': false,
                        
                        // MFI - green
                        'money flow index.plot.color': '#10B981',
                        'money flow index.plot.linewidth': 2,
                        'money flow index.hline.color': 'rgba(255,255,255,0.2)',
                        'money flow index.show_last_value': false,
                        
                        // VWAP - distinctive gold
                        'vwap.plot.color': '#FFD700',
                        'vwap.plot.linewidth': 2,
                        'vwap.show_last_value': false,
                        
                        // Ichimoku Cloud - muted colors to not overwhelm
                        'ichimoku cloud.leading span a.color': 'rgba(34, 197, 94, 0.3)',
                        'ichimoku cloud.leading span b.color': 'rgba(239, 68, 68, 0.3)',
                        'ichimoku cloud.lagging span.color': '#A78BFA',
                        'ichimoku cloud.conversion line.color': '#06B6D4',
                        'ichimoku cloud.base line.color': '#EF4444',
                        'ichimoku cloud.show_last_value': false
                      }
                    });
                    showContainer();

                    if (window.tvWidget && window.tvWidget.onChartReady) {
                      window.tvWidget.onChartReady(function(){
                        try {
                          // Studies are already initialized via widget constructor
                          // Just set up symbol/interval and haptic hooks
                          tryApplySymbol(cfg.symbol, cfg.interval, cfg.altSymbols);
                          try { installHapticsHooks(); } catch(e){}
                          // Subscribe to crosshair moves for haptic feedback
                          // NOTE: These fire very frequently - throttled at postHaptic level to prevent crash
                          try {
                            var chart = window.tvWidget.chart();
                            if (chart && !chart._hapticCrosshairHook) {
                              chart._hapticCrosshairHook = true;
                              if (chart.onCrossHairMove) {
                                chart.onCrossHairMove().subscribe(null, function(){ try { if (window.postHaptic) window.postHaptic('tick'); } catch(e){} });
                              } else if (chart.onCrosshairMove) {
                                chart.onCrosshairMove().subscribe(null, function(){ try { if (window.postHaptic) window.postHaptic('tick'); } catch(e){} });
                              }
                            }
                          } catch(e){}
                        } catch(e){}
                        try { window.webkit.messageHandlers.tvlog.postMessage({ type: 'ready' }); } catch(e){}
                        showContainer();
                      });
                    }
                    // Failsafe: ensure container becomes visible even if onChartReady is slow
                    setTimeout(function(){ try { showContainer(); } catch(e){} }, 500);
                    window._currentSymbol = cfg.symbol;
                    window._currentInterval = cfg.interval;
                  } else {
                    // Widget exists - only symbol/interval changes (studies handled via recreate)
                    var symbolChanged = (cfg.symbol !== window._currentSymbol);
                    var intervalChanged = (cfg.interval !== window._currentInterval);
                    
                    console.log('[TV] No recreate needed. Symbol changed: ' + symbolChanged + ', Interval changed: ' + intervalChanged);
                    console.log('[TV] Current: ' + window._currentSymbol + '@' + window._currentInterval + ' -> New: ' + cfg.symbol + '@' + cfg.interval);
                    
                    if (symbolChanged || intervalChanged) {
                      tryApplySymbol(cfg.symbol, cfg.interval, cfg.altSymbols);
                      try { installHapticsHooks(); } catch(e){}
                      window._currentSymbol = cfg.symbol;
                      window._currentInterval = cfg.interval;
                    }
                  }
                } catch (e) { /* swallow */ }
              }

              // Expose explicitly for Swift bridge
              window.renderTV = renderTV;

              // Load TradingView script once
              (function(){
                var s = document.createElement('script');
                s.src = 'https://s3.tradingview.com/tv.js';
                s.async = true; s.defer = true; s.crossOrigin = 'anonymous';
                try { s.fetchPriority = 'high'; } catch(e){}
                s.onload = function(){ if (window._pendingCfg) { var c = window._pendingCfg; window._pendingCfg = null; renderTV(c.symbol, c.interval, c.theme, c.studies, c.altSymbols); } };
                document.head.appendChild(s);
              })();
            </script>
          </head>
          <body>
            <div id=\"tv_chart_container\"></div>
          </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://s3.tradingview.com"))
    }
    
    @MainActor class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var ready: Binding<Bool>?
        var loadingTimer: Timer?
        
        init(ready: Binding<Bool>?) { self.ready = ready }
        
        var lastSymbol: String = ""
        var lastInterval: String = ""
        var lastTheme: String = ""
        var lastStudies: [String] = []
        var lastInteractive: Bool = false
        var lastAltSymbols: [String] = []
        var pageLoaded: Bool = false
        
        var appliedSymbol: String = ""
        var appliedInterval: String = ""
        var appliedTheme: String = ""
        var appliedStudies: [String] = []
        var appliedInteractive: Bool = false
        var appliedAltSymbols: [String] = []
        
        // PERFORMANCE FIX: Rate limiting for message handler to prevent queue saturation
        // This prevents the "Message send exceeds rate-limit threshold" warnings
        private var lastLogMessageAt: Date = .distantPast
        private var lastHapticMessageAt: Date = .distantPast
        private let logMessageThrottle: TimeInterval = 0.1  // Max 10 log messages per second
        private let hapticMessageThrottle: TimeInterval = 0.016  // Max 60 haptic messages per second (for smooth feedback)
        private var droppedMessageCount: Int = 0
        
        func webView(_ webView: WKWebView,
                     didFinish navigation: WKNavigation!) {
            pageLoaded = true
            // Cancel loading timeout - page loaded successfully
            loadingTimer?.invalidate()
            loadingTimer = nil
            let js = Coordinator.buildRenderJS(symbol: lastSymbol, interval: lastInterval, theme: lastTheme, studies: lastStudies, altSymbols: lastAltSymbols)
            webView.evaluateJavaScript(js, completionHandler: nil)
            self.appliedSymbol = self.lastSymbol
            self.appliedInterval = self.lastInterval
            self.appliedTheme = self.lastTheme
            self.appliedStudies = self.lastStudies
            self.appliedAltSymbols = self.lastAltSymbols

            let interJS = Coordinator.buildSetInteractivityJS(enabled: self.lastInteractive)
            webView.evaluateJavaScript(interJS, completionHandler: nil)
            self.appliedInteractive = self.lastInteractive

            let earlyShowJS = "try{ showContainer(); }catch(e){}"
            webView.evaluateJavaScript(earlyShowJS, completionHandler: nil)
            DispatchQueue.main.async { self.ready?.wrappedValue = true }
            
            #if DEBUG
            // print("TradingView web content finished loading.")
            #endif
        }
        
        func webView(_ webView: WKWebView,
                     didFail navigation: WKNavigation!,
                     withError error: Error) {
            fallbackMessage(in: webView)
            DispatchQueue.main.async { self.ready?.wrappedValue = true }
        }
        
        // SECURITY: Restrict WebView navigation to TradingView domains only.
        // Prevents embedded content or injected scripts from navigating to phishing pages.
        private static let allowedHosts: Set<String> = [
            "s3.tradingview.com",
            "s.tradingview.com",
            "tradingview.com",
            "www.tradingview.com",
            "pine-facade.tradingview.com",
            "scanner.tradingview.com",
        ]
        
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            // Allow data: and about: schemes (used by loadHTMLString)
            if url.scheme == "about" || url.scheme == "data" {
                decisionHandler(.allow)
                return
            }
            // Allow only HTTPS to known TradingView hosts
            if url.scheme == "https", let host = url.host?.lowercased(),
               Self.allowedHosts.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) {
                decisionHandler(.allow)
                return
            }
            #if DEBUG
            print("[TradingViewChart] Blocked navigation to: \(url.absoluteString)")
            #endif
            decisionHandler(.cancel)
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
        
        /// Escape a string for safe embedding inside a JS single-quoted literal
        private static func jsEscape(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "'", with: "\\'")
             .replacingOccurrences(of: "\n", with: "\\n")
             .replacingOccurrences(of: "\r", with: "\\r")
        }
        
        static func buildRenderJS(symbol: String, interval: String, theme: String, studies: [String], altSymbols: [String]) -> String {
            // If study string starts with '{', assume it's a JSON descriptor, insert as-is.
            // Else quote the string normally.
            let studiesJS = studies.map { study -> String in
                let trimmed = study.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.first == "{" {
                    return trimmed
                } else {
                    return "'\(jsEscape(trimmed))'"
                }
            }.joined(separator: ",")
            let altsJS = altSymbols.map { s in
                return "'\(jsEscape(s.trimmingCharacters(in: .whitespacesAndNewlines)))'"
            }.joined(separator: ",")
            return "window.renderTV('\(jsEscape(symbol))','\(jsEscape(interval))','\(jsEscape(theme))',[\(studiesJS)],[\(altsJS)]);"
        }

        static func buildSetInteractivityJS(enabled: Bool) -> String {
            return "try{ if (window.setTVInteractivity) window.setTVInteractivity(" + (enabled ? "true" : "false") + "); }catch(e){}"
        }

        // Bridge JS console to Xcode logs for visibility into tv.js behavior and handle haptics messages
        // PERFORMANCE FIX: Rate-limited to prevent "Message send exceeds rate-limit threshold" warnings
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            let now = Date()
            
            if message.name == "tvlog" {
                // Always process "ready" messages immediately - critical for initialization
                if let dict = message.body as? [String: Any], let type = dict["type"] as? String, type == "ready" {
                    DispatchQueue.main.async { self.ready?.wrappedValue = true }
                    return
                }
                
                // PERFORMANCE FIX: Rate limit log messages to prevent queue saturation
                guard now.timeIntervalSince(lastLogMessageAt) >= logMessageThrottle else {
                    droppedMessageCount += 1
                    return  // Drop this message - too soon since last one
                }
                lastLogMessageAt = now
                
                // Log dropped message count periodically (every 100 drops)
                #if DEBUG
                if droppedMessageCount > 0 && droppedMessageCount % 100 == 0 {
                    print("[TV] Rate limiting: dropped \(droppedMessageCount) messages")
                }
                #endif
                
                if let dict = message.body as? [String: Any], let payload = dict["payload"] {
                    let text: String
                    if let arr = payload as? [Any] {
                        text = arr.map { String(describing: $0) }.joined(separator: " ")
                    } else {
                        text = String(describing: payload)
                    }
                    let lower = text.lowercased()
                    if lower.contains("does not exist") || lower.contains("unknown property") || lower.contains("unknown parameter") || lower.contains("is deprecated") || lower.contains("show_last_value") || lower.contains("has no plot") || lower.contains("has no input") || lower.contains("studypropertiesoverrider") {
                        return // suppress benign schema warnings
                    }
                }
                #if DEBUG
                print("[TV]", message.body)
                #endif
            } else if message.name == "haptics" {
                // PERFORMANCE FIX: Rate limit haptic messages (but allow higher frequency for smooth feedback)
                guard now.timeIntervalSince(lastHapticMessageAt) >= hapticMessageThrottle else {
                    return  // Drop this haptic - too soon
                }
                lastHapticMessageAt = now
                
                if let dict = message.body as? [String: Any], let type = dict["type"] as? String {
                    switch type {
                    case "begin":
                        ChartHaptics.shared.begin()
                    case "end":
                        ChartHaptics.shared.end()
                    case "tick":
                        ChartHaptics.shared.tickIfNeeded()
                    case "major":
                        ChartHaptics.shared.majorIfNeeded()
                    case "grid":
                        ChartHaptics.shared.gridBumpIfNeeded()
                    case "success":
                        ChartHaptics.shared.success()
                    case "warning":
                        ChartHaptics.shared.warning()
                    case "error":
                        ChartHaptics.shared.error()
                    default:
                        break // ignore unknown types
                    }
                }
            }
        }
    }
}

