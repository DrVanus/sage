//
//  CoinDetailView.swift
//  CSAI1
//
//  Cleaned-up version with no duplicate CoinDetailTradingViewWebView
//

import SwiftUI
// import Charts
import WebKit
import Combine

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
        case .live:       return "LIVE"
        default: return ""
        }
    }
}

// MARK: - ChartType
enum ChartType: String, CaseIterable {
    case cryptoSageAI = "CryptoSage AI"
    case tradingView  = "TradingView"
}

// MARK: - CoinDetailView
struct CoinDetailView: View {
    let coin: MarketCoin

    @State private var selectedChartType: ChartType = .cryptoSageAI
    @State private var selectedInterval: ChartInterval = .oneDay

    @State private var currentPrice: Double
    @State private var change24h: Double
    @State private var livePriceCancellable: AnyCancellable?

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.presentationMode) var presentationMode

    init(coin: MarketCoin) {
        self.coin = coin
        _currentPrice = State(initialValue: coin.priceUsd ?? 0)
        _change24h     = State(initialValue: coin.dailyChange)
    }

    private var tvSymbol: String {
        "BINANCE:\(coin.symbol.uppercased())USDT"
    }

    private var tvTheme: String {
        colorScheme == .dark ? "Dark" : "Light"
    }

    var body: some View {
        ZStack {
            FuturisticBackground()
                .ignoresSafeArea()

            contentScrollView
            tradeButtonStack
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            LivePriceManager.shared.startPolling()
            livePriceCancellable = LivePriceManager.shared.coinsPublisher
                .receive(on: DispatchQueue.main)
                .sink { coins in
                    if let updated = coins.first(where: { $0.id == coin.id }),
                       let price = updated.priceUsd {
                        currentPrice = price
                        change24h     = updated.dailyChange
                    }
                }
        }
        .onDisappear {
            livePriceCancellable?.cancel()
        }
    }

    // MARK: - Main Scroll Content
    private var contentScrollView: some View {
        ScrollView {
            VStack(spacing: 16) {
                navBar
                chartSection
                intervalRow
                chartTypeToggle
                statsCardView
            }
            .padding()
            .padding(.bottom, 100)
        }
    }

    // MARK: - Stats Card View
    private var statsCardView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Live Coin Data")
                .font(.headline)
                .foregroundColor(.white)

            coreStatsView

            extendedStatsView
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.yellow.opacity(0.2), lineWidth: 1)
        )
        .cornerRadius(20)
        .padding(.horizontal, 16)
        .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 5)
    }

    // MARK: - Core Stats View
    private var coreStatsView: some View {
        VStack(spacing: 12) {
            // Price (USD)
            HStack {
                Text("Price (USD)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                Spacer()
                Text(formatPrice(currentPrice))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            Divider().background(Color.white.opacity(0.25))

            // 24h Change
            HStack {
                Text("24h Change")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                Spacer()
                Text(String(format: "%.2f%%", change24h))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(change24h >= 0 ? .green : .red)
            }
            Divider().background(Color.white.opacity(0.25))

            // Market Cap
            HStack {
                Text("Market Cap")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                Spacer()
                Text(formatLargeNumber(coin.marketCap ?? 0))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
            Divider().background(Color.white.opacity(0.25))

            // Volume (24h)
            HStack {
                Text("Volume (24h)")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                Spacer()
                Text(formatLargeNumber(coin.volumeUsd24Hr ?? 0))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
        }
    }

    // MARK: - Extended Stats View
    private var extendedStatsView: some View {
        VStack(spacing: 12) {
            Divider().background(Color.white.opacity(0.25))


            // Rank
            HStack {
                Text("Rank")
                    .font(.subheadline)
                    .foregroundColor(coin.marketCapRank != nil ? .gray : .gray.opacity(0.5))
                Spacer()
                if let rank = coin.marketCapRank {
                    Text("\(rank)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                } else {
                    Text("–")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            Divider().background(Color.white.opacity(0.25))

            // Max Supply
            HStack {
                Text("Max Supply")
                    .font(.subheadline)
                    .foregroundColor(coin.maxSupply > 0 ? .gray : .gray.opacity(0.5))
                Spacer()
                if coin.maxSupply > 0 {
                    Text(formatLargeNumber(coin.maxSupply))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                } else {
                    Text("–")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
    }

    // MARK: - Trade Button Stack
    private var tradeButtonStack: some View {
        VStack {
            Spacer()
            tradeButton
        }
    }
    
    // MARK: - Nav Bar
    private var navBar: some View {
        ZStack {
            // Left: Back button
            HStack {
                Button {
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(.yellow)
                        Text("Back")
                            .foregroundColor(.yellow)
                    }
                }
                Spacer()
            }
            
            // Center: Icon + symbol + price
            HStack {
                Spacer()
                VStack(spacing: 2) {
                    if let uiImage = UIImage(named: coin.symbol.lowercased()) {
                        HStack(spacing: 6) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 24, height: 24)
                                .clipShape(Circle())
                            Text(coin.symbol.uppercased())
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                        }
                    } else {
                        Text(coin.symbol.uppercased())
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                    }
                    
                    Text(formatPrice(coin.priceUsd ?? 0))
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundColor(.yellow)
                }
                Spacer()
            }
        }
        .padding(.vertical, 8)
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 1),
            alignment: .bottom
        )
    }
    
    // MARK: - Chart Section
    @ViewBuilder
    private var chartSection: some View {
        if selectedChartType == .cryptoSageAI {
            CryptoChartView(symbol: coin.symbol,
                            interval: selectedInterval,
                            height: 330)
                .padding(.vertical, 8)
        } else {
            CoinDetailTradingViewWebView(symbol: tvSymbol,
                                         interval: selectedInterval.tvValue,
                                         theme: tvTheme)
                .frame(height: 330)
                .padding(.vertical, 8)
        }
    }
    
    // MARK: - Interval Row
    private var intervalRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ChartInterval.allCases, id: \.self) { interval in
                    Button {
                        selectedInterval = interval
                    } label: {
                        Text(interval.rawValue)
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(selectedInterval == interval ? .yellow : Color.white.opacity(0.15))
                            )
                            .foregroundColor(selectedInterval == interval ? .black : .white)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    // MARK: - Chart Type Toggle
    private var chartTypeToggle: some View {
        HStack(spacing: 0) {
            ForEach(ChartType.allCases, id: \.self) { type in
                Button {
                    selectedChartType = type
                } label: {
                    Text(type.rawValue)
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundColor(selectedChartType == type ? .black : .white)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(selectedChartType == type ? .yellow : Color.white.opacity(0.15))
                }
            }
        }
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
    
    // MARK: - Trade Button
    private var tradeButton: some View {
        Button(action: {
            // Insert your trade action here
        }) {
            Text("Trade \(coin.symbol.uppercased())")
                .font(.headline)
                .foregroundColor(.black)
                .padding()
                .frame(maxWidth: .infinity)
                .background(.yellow)
                .cornerRadius(12)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .background(Color.black.opacity(0.8))
        .shadow(color: Color.black.opacity(0.6), radius: 10, x: 0, y: -3)
    }
    
    // MARK: - Price Formatter
    private func formatPrice(_ value: Double) -> String {
        guard value > 0 else { return "$0.00" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        if value < 1.0 {
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 8
        } else {
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
        }
        return "$" + (formatter.string(from: NSNumber(value: value)) ?? "0.00")
    }

    // MARK: - Large Number Formatter
    private func formatLargeNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        if value >= 1_000_000_000 {
            let shortVal = value / 1_000_000_000
            return formatter.string(from: NSNumber(value: shortVal)).map { "\($0)B" } ?? "--"
        } else if value >= 1_000_000 {
            let shortVal = value / 1_000_000
            return formatter.string(from: NSNumber(value: shortVal)).map { "\($0)M" } ?? "--"
        } else if value >= 1_000 {
            let shortVal = value / 1_000
            return formatter.string(from: NSNumber(value: shortVal)).map { "\($0)K" } ?? "--"
        } else {
            return formatter.string(from: NSNumber(value: value)) ?? String(value)
        }
    }
}


// MARK: - CoinDetailTradingViewWebView
// (Only one definition remains—duplicate was removed)
struct CoinDetailTradingViewWebView: UIViewRepresentable {
    let symbol: String
    let interval: String
    let theme: String
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        loadHTML(into: webView)
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        loadHTML(into: uiView)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    private func loadHTML(into webView: WKWebView) {
        let html = """
        <!DOCTYPE html>
        <html>
          <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
              html, body { margin: 0; padding: 0; height: 100%; background: transparent; }
              #tv_chart_container { width:100%; height:100%; }
            </style>
          </head>
          <body>
            <div id="tv_chart_container"></div>
            <script src="https://www.tradingview.com/tv.js"></script>
            <script>
              try {
                new TradingView.widget({
                  "container_id": "tv_chart_container",
                  "symbol": "\(symbol)",
                  "interval": "\(interval)",
                  "timezone": "Etc/UTC",
                  "theme": "\(theme)",
                  "style": "1",
                  "locale": "en",
                  "toolbar_bg": "#f1f3f6",
                  "enable_publishing": false,
                  "allow_symbol_change": true,
                  "autosize": true
                });
              } catch(e) {
                document.body.innerHTML = "<h3 style='color:yellow;text-align:center;margin-top:40px;'>TradingView is blocked in your region.</h3>";
              }
            </script>
          </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://www.tradingview.com"))
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView,
                     didFinish navigation: WKNavigation!) {
            print("TradingView web content finished loading.")
        }
        
        func webView(_ webView: WKWebView,
                     didFail navigation: WKNavigation!,
                     withError error: Error) {
            fallbackMessage(in: webView)
        }
        
        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            fallbackMessage(in: webView)
        }
        
        private func fallbackMessage(in webView: WKWebView) {
            let fallbackHTML = """
            <html><body style="background:transparent;color:yellow;text-align:center;padding-top:40px;">
            <h3>TradingView is blocked in your region or unavailable.</h3>
            <p>Try a VPN or different region.</p>
            </body></html>
            """
            webView.loadHTMLString(fallbackHTML, baseURL: nil)
        }
    }
}

