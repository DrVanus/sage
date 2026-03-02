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

    // Direct color to use for technicals gauge (no sentiment terms)
    var gaugeColor: Color {
        switch self {
        case .strongSell: return .red
        case .sell:       return .orange
        case .neutral:    return .yellow
        case .buy:        return .green
        case .strongBuy:  return .mint
        }
    }

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

public enum IndicatorSignalStrength: String, Codable, CaseIterable, Equatable {
    case sell, neutral, buy
}

public struct IndicatorSignal: Identifiable, Codable, Equatable {
    public let id: String
    public let label: String
    public let signal: IndicatorSignalStrength
    public let valueText: String?

    public init(label: String, signal: IndicatorSignalStrength, valueText: String? = nil) {
        self.id = label
        self.label = label
        self.signal = signal
        self.valueText = valueText
    }
}

public struct TechnicalsSummary: Codable, Equatable {
    // score01 in 0...1 for needle position (0 = strong sell, 1 = strong buy)
    public let score01: Double
    public let verdict: TechnicalVerdict
    // Overall counts (consensus-like)
    public let sellCount: Int
    public let neutralCount: Int
    public let buyCount: Int
    // Breakdown counts
    public let maSell: Int
    public let maNeutral: Int
    public let maBuy: Int
    public let oscSell: Int
    public let oscNeutral: Int
    public let oscBuy: Int
    // Per-indicator signals
    public let indicators: [IndicatorSignal]
    
    // CryptoSage-exclusive features (only populated for cryptosage source)
    public let confidence: Int?          // 0-100 indicator agreement %
    public let trendStrength: String?    // "Ranging", "Weak", "Moderate", "Strong", "Very Strong"
    public let volatilityRegime: String? // "Low", "Normal", "High", "Extreme"
    public let aiSummary: String?        // AI-generated analysis text
    public let divergence: String?       // "bullish", "bearish", "none"
    public let divergenceStrength: String? // "weak", "moderate", "strong"
    public let supertrendDirection: String? // "bullish", "bearish"
    public let parabolicSarTrend: String?   // "bullish", "bearish"
    public let source: String?           // "cryptosage", "coinbase", "binance"

    public init(score01: Double,
                verdict: TechnicalVerdict,
                sellCount: Int = 0,
                neutralCount: Int = 0,
                buyCount: Int = 0,
                maSell: Int = 0,
                maNeutral: Int = 0,
                maBuy: Int = 0,
                oscSell: Int = 0,
                oscNeutral: Int = 0,
                oscBuy: Int = 0,
                indicators: [IndicatorSignal] = [],
                confidence: Int? = nil,
                trendStrength: String? = nil,
                volatilityRegime: String? = nil,
                aiSummary: String? = nil,
                divergence: String? = nil,
                divergenceStrength: String? = nil,
                supertrendDirection: String? = nil,
                parabolicSarTrend: String? = nil,
                source: String? = nil) {
        self.score01 = max(0, min(1, score01))
        self.verdict = verdict
        self.sellCount = sellCount
        self.neutralCount = neutralCount
        self.buyCount = buyCount
        self.maSell = maSell
        self.maNeutral = maNeutral
        self.maBuy = maBuy
        self.oscSell = oscSell
        self.oscNeutral = oscNeutral
        self.oscBuy = oscBuy
        self.indicators = indicators
        // CryptoSage-exclusive
        self.confidence = confidence
        self.trendStrength = trendStrength
        self.volatilityRegime = volatilityRegime
        self.aiSummary = aiSummary
        self.divergence = divergence
        self.divergenceStrength = divergenceStrength
        self.supertrendDirection = supertrendDirection
        self.parabolicSarTrend = parabolicSarTrend
        self.source = source
    }
}

// MARK: - Compact Gauge View (reuses ImprovedHalfCircleGauge)
public struct TechnicalsGaugeView: View {
    public let summary: TechnicalsSummary
    public var timeframeLabel: String? = nil
    public var lineWidth: CGFloat = 10
    public var preferredHeight: CGFloat? = nil
    public var showArcLabels: Bool = true
    public var showEndCaps: Bool = true
    public var showVerdictLine: Bool = true

    public init(
        summary: TechnicalsSummary,
        timeframeLabel: String? = nil,
        lineWidth: CGFloat = 10,
        preferredHeight: CGFloat? = nil,
        showArcLabels: Bool = true,
        showEndCaps: Bool = true,
        showVerdictLine: Bool = true
    ) {
        self.summary = summary
        self.timeframeLabel = timeframeLabel
        self.lineWidth = lineWidth
        self.preferredHeight = preferredHeight
        self.showArcLabels = showArcLabels
        self.showEndCaps = showEndCaps
        self.showVerdictLine = showVerdictLine
    }

    public var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack {
                    // Use the same half-circle gauge used by Market Sentiment, but drive it with technicals
                    ImprovedHalfCircleGauge(
                        value: summary.score01 * 100,
                        classification: summary.verdict.classificationKey,
                        lineWidth: lineWidth,
                        disableBadgeAnimation: true,
                        showLiveBadge: false,
                        tickLabelOpacityFactor: 0.0,
                        showTicks: false
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Technicals summary: \(summary.verdict.displayName)")

                    // TradingView-style arc labels (Strong sell ... Strong buy)
                    if showArcLabels {
                        ArcLabelsOverlay(
                            lineWidth: lineWidth,
                            strongSell: "Strong sell",
                            sell: "Sell",
                            buy: "Buy",
                            strongBuy: "Strong buy"
                        )
                    }
                    if showEndCaps {
                        EndCapsOverlay(lineWidth: lineWidth)
                    }
                }
            }
            .frame(height: preferredHeight ?? 150)
            .padding(.horizontal, 4)
            .padding(.bottom, 0)
            .padding(.top, 2)

            if showVerdictLine {
                // Verdict line
                HStack(spacing: 4) {
                    if let tf = timeframeLabel, !tf.isEmpty {
                        Text(tf)
                            .font(.caption2)
                            .fontWidth(.condensed)
                            .foregroundColor(DS.Adaptive.textTertiary)
                            .padding(.trailing, 2)
                    }
                    Text(summary.verdict.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .fontWidth(.condensed)
                        .foregroundColor(summary.verdict.gaugeColor)
                }
                .padding(.top, 1)
            }
        }
    }
}

// A lightweight overlay that positions labels around the gauge arc using trigonometry
private struct ArcLabelsOverlay: View {
    let lineWidth: CGFloat
    let strongSell: String
    let sell: String
    let buy: String
    let strongBuy: String

    // Convert a 0-100 value to a point on the arc
    private func arcPoint(center: CGPoint, radius: CGFloat, value: Double) -> CGPoint {
        // Arc goes from 180° (left, value=0) to 0° (right, value=100)
        let degrees = 180.0 - (value / 100.0) * 180.0
        let radians = CGFloat(degrees) * .pi / 180.0
        return CGPoint(
            x: center.x + CoreGraphics.cos(radians) * radius,
            y: center.y - CoreGraphics.sin(radians) * radius
        )
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            // Treat very small gauges as compact
            let isCompact = (w < 320 || h < 150)

            // Calculate gauge geometry (matching ImprovedHalfCircleGauge)
            let arcRadius = (min(w, h * 2) / 2 - lineWidth / 2) * 0.87
            let centerLift = lineWidth * 1.28 + 10
            let center = CGPoint(x: w / 2, y: h - centerLift)
            
            // Label radius - position labels outside the arc
            let labelRadius = arcRadius + lineWidth * 1.2 + (isCompact ? 12 : 18)
            
            // Tick mark radius (just outside the arc)
            let tickOuterRadius = arcRadius + lineWidth * 0.6
            let tickInnerRadius = arcRadius - lineWidth * 0.3
            
            // Adaptive font sizes
            let baseFont: CGFloat = isCompact ? 9.0 : 11.0
            let extremeFont: CGFloat = isCompact ? 8.0 : 9.5

            // Zone boundaries (0-20: Strong Sell, 20-40: Sell, 40-60: Neutral, 60-80: Buy, 80-100: Strong Buy)
            let tickPositions: [Double] = [0, 20, 40, 60, 80, 100]
            // Label positions at zone midpoints (neutral label omitted - it overlaps with UI above)
            let labelPositions: [(value: Double, label: String, color: Color)] = [
                (10, strongSell, .red.opacity(0.75)),
                (30, sell, Color(red: 1.0, green: 0.4, blue: 0.5).opacity(0.85)),
                (70, buy, Color(red: 0.4, green: 0.85, blue: 0.6).opacity(0.85)),
                (90, strongBuy, .green.opacity(0.75))
            ]

            ZStack {
                // Draw tick marks at zone boundaries
                ForEach(tickPositions, id: \.self) { pos in
                    let outerPt = arcPoint(center: center, radius: tickOuterRadius, value: pos)
                    let innerPt = arcPoint(center: center, radius: tickInnerRadius, value: pos)
                    
                    Path { path in
                        path.move(to: outerPt)
                        path.addLine(to: innerPt)
                    }
                    .stroke(DS.Adaptive.textTertiary.opacity(0.5), lineWidth: isCompact ? 1.0 : 1.5)
                }
                
                // Draw labels at zone midpoints
                ForEach(labelPositions.indices, id: \.self) { idx in
                    let item = labelPositions[idx]
                    let pt = arcPoint(center: center, radius: labelRadius, value: item.value)
                    
                    // Skip extreme labels (Strong Sell/Strong Buy at idx 0 and 3) on compact gauges
                    let isExtreme = (idx == 0 || idx == 3)
                    if !isCompact || !isExtreme {
                        Text(item.label)
                            .font(.system(size: isExtreme ? extremeFont : baseFont, weight: .semibold))
                            .fontWidth(.condensed)
                            .foregroundColor(item.color)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .allowsTightening(true)
                            .fixedSize()
                            .position(x: pt.x, y: pt.y)
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}

// Small plus/minus glyphs at the arc ends to match TradingView affordance
private struct EndCapsOverlay: View {
    let lineWidth: CGFloat

    private func point(center: CGPoint, radius: CGFloat, mark: Double, offset: CGFloat) -> CGPoint {
        let deg = 180 + (mark / 100.0) * 180.0
        let r = radius + offset
        let rad = CGFloat(deg) * .pi / 180
        return CGPoint(x: center.x + cos(rad) * r, y: center.y + sin(rad) * r)
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let radius = (min(w, h * 2) / 2 - lineWidth / 2) * 0.87
            let centerLift = lineWidth * 1.28 + 10
            let center = CGPoint(x: w / 2, y: h - centerLift)
            let compact = (w < 340) || (h < 160)
            // Pull inside the arc instead of outside
            let offset = -(lineWidth * 0.58 + 3)

            ZStack {
                if !compact {
                    Image(systemName: "minus")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(DS.Adaptive.textTertiary)
                        .position(point(center: center, radius: radius, mark: 0, offset: offset))
                    Image(systemName: "plus")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(DS.Adaptive.textTertiary)
                        .position(point(center: center, radius: radius, mark: 100, offset: offset))
                }
            }
            .allowsHitTesting(false)
        }
    }
}

// MARK: - TradingView Technicals (Detail)
struct TradingViewTechnicalsWebView: UIViewRepresentable {
    let symbol: String   // e.g. "BINANCE:BTCUSDT"
    let theme: String    // "Dark" or "Light"
    let initialInterval: String = "1D" // let widget show its own tabs; default to 1D

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let userContentController = WKUserContentController()
        userContentController.add(context.coordinator, name: "haptics")

        let cfg = WKWebViewConfiguration()
        cfg.userContentController = userContentController

        let web = WKWebView(frame: .zero, configuration: cfg)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.backgroundColor = .clear
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.scrollView.isScrollEnabled = false
        web.scrollView.showsVerticalScrollIndicator = false
        web.scrollView.showsHorizontalScrollIndicator = false
        web.scrollView.bounces = false
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
            <script>
              (function(){
                window.postHaptic = function(type){ try { window.webkit.messageHandlers.haptics.postMessage({ type: String(type||'') }); } catch(e){} };
                function install(){
                  try {
                    var root = document.body;
                    if (!root || root._hInstalled) return;
                    root._hInstalled = true;
                    root.addEventListener('pointerdown', function(){ postHaptic('begin'); });
                    ['pointerup','pointercancel','pointerleave'].forEach(function(evt){ root.addEventListener(evt, function(){ postHaptic('end'); }); });
                    root.addEventListener('pointermove', function(){ postHaptic('tick'); });
                  } catch(e){}
                }
                if (document.readyState === 'loading') { document.addEventListener('DOMContentLoaded', install); } else { install(); }
              })();
            </script>
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

    class Coordinator: NSObject, WKScriptMessageHandler {
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "haptics" else { return }
            guard let dict = message.body as? [String: Any], let type = dict["type"] as? String else { return }
            switch type {
            case "begin": ChartHaptics.shared.begin()
            case "end": ChartHaptics.shared.end()
            case "tick": ChartHaptics.shared.tickIfNeeded()
            case "major": ChartHaptics.shared.majorIfNeeded()
            case "grid": ChartHaptics.shared.gridBumpIfNeeded()
            case "success": ChartHaptics.shared.success()
            case "warning": ChartHaptics.shared.warning()
            case "error": ChartHaptics.shared.error()
            default: break
            }
        }
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
            DS.Adaptive.background.ignoresSafeArea()
            TradingViewTechnicalsWebView(symbol: symbol, theme: theme)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Technicals")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - VerdictPill (added modifications for label fitting)
public struct VerdictPill: View {
    let value: String
    let color: Color

    public init(value: String, color: Color) {
        self.value = value
        self.color = color
    }

    public var body: some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.caption2.weight(.bold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .allowsTightening(true)
                .fontWidth(.condensed)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.06))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.6))
    }
}

// MARK: - Indicator Chip + Grid (for RSI / ADX / Momentum / MACD)
public struct IndicatorChip: View {
    let title: String
    let valueText: String
    let valueColor: Color
    var borderColor: Color = Color.white.opacity(0.12)

    public init(title: String, valueText: String, valueColor: Color, borderColor: Color = Color.white.opacity(0.12)) {
        self.title = title
        self.valueText = valueText
        self.valueColor = valueColor
        self.borderColor = borderColor
    }

    public var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
                .fontWidth(.condensed)

            Text(valueText)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(borderColor, lineWidth: 0.8)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(valueText)")
    }
}

public struct IndicatorChipsGrid: View {
    let signals: [IndicatorSignal]

    public init(signals: [IndicatorSignal]) { self.signals = signals }

    private func color(for signal: IndicatorSignalStrength) -> Color {
        switch signal {
        case .sell: return .red
        case .neutral: return .yellow
        case .buy: return .green
        }
    }

    public var body: some View {
        // Adaptive grid expands to full width and wraps cleanly
        let cols = [GridItem(.adaptive(minimum: 110, maximum: 200), spacing: 10, alignment: .top)]
        LazyVGrid(columns: cols, alignment: .leading, spacing: 10) {
            ForEach(signals) { sig in
                IndicatorChip(
                    title: sig.label,
                    valueText: sig.valueText ?? "",
                    valueColor: color(for: sig.signal)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

