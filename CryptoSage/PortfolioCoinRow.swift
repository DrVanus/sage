//
//  PortfolioCoinRow.swift
//  CSAI1
//
//  Created by DM on 3/26/25.
//

import SwiftUI

/// Hardcoded reliable CoinGecko image URLs for common coins - these never fail
private let CoinIconFallbacks: [String: URL] = [
    "btc": URL(string: "https://coin-images.coingecko.com/coins/images/1/large/bitcoin.png")!,
    "eth": URL(string: "https://coin-images.coingecko.com/coins/images/279/large/ethereum.png")!,
    "sol": URL(string: "https://coin-images.coingecko.com/coins/images/4128/large/solana.png")!,
    "xrp": URL(string: "https://coin-images.coingecko.com/coins/images/44/large/xrp-symbol-white-128.png")!,
    "bnb": URL(string: "https://coin-images.coingecko.com/coins/images/825/large/binance-coin-logo.png")!,
    "ada": URL(string: "https://coin-images.coingecko.com/coins/images/975/large/cardano.png")!,
    "doge": URL(string: "https://coin-images.coingecko.com/coins/images/5/large/dogecoin.png")!,
    "ltc": URL(string: "https://coin-images.coingecko.com/coins/images/2/large/litecoin.png")!,
    "dot": URL(string: "https://coin-images.coingecko.com/coins/images/12171/large/polkadot.png")!,
    "usdt": URL(string: "https://coin-images.coingecko.com/coins/images/325/large/Tether.png")!,
    "usdc": URL(string: "https://coin-images.coingecko.com/coins/images/6319/large/USD_Coin_icon.png")!,
    "avax": URL(string: "https://coin-images.coingecko.com/coins/images/12559/large/Avalanche_Circle_RedWhite_Trans.png")!,
    "link": URL(string: "https://coin-images.coingecko.com/coins/images/877/large/chainlink-new-logo.png")!,
    "matic": URL(string: "https://coin-images.coingecko.com/coins/images/4713/large/polygon.png")!,
    "atom": URL(string: "https://coin-images.coingecko.com/coins/images/1481/large/cosmos_hub.png")!,
    "uni": URL(string: "https://coin-images.coingecko.com/coins/images/12504/large/uniswap-logo.png")!,
    "shib": URL(string: "https://coin-images.coingecko.com/coins/images/11939/large/shiba.png")!,
    "trx": URL(string: "https://coin-images.coingecko.com/coins/images/1094/large/tron-logo.png")!,
    "xlm": URL(string: "https://coin-images.coingecko.com/coins/images/100/large/Stellar_symbol_black_RGB.png")!,
    "near": URL(string: "https://coin-images.coingecko.com/coins/images/10365/large/near.jpg")!,
    "apt": URL(string: "https://coin-images.coingecko.com/coins/images/26455/large/aptos_round.png")!,
    "arb": URL(string: "https://coin-images.coingecko.com/coins/images/16547/large/photo_2023-03-29_21.47.00.jpeg")!,
    "op": URL(string: "https://coin-images.coingecko.com/coins/images/25244/large/Optimism.png")!,
    "sui": URL(string: "https://coin-images.coingecko.com/coins/images/26375/large/sui_asset.jpeg")!,
    "fil": URL(string: "https://coin-images.coingecko.com/coins/images/12817/large/filecoin.png")!,
    "inj": URL(string: "https://coin-images.coingecko.com/coins/images/12882/large/Secondary_Symbol.png")!,
    "hbar": URL(string: "https://coin-images.coingecko.com/coins/images/3688/large/hbar.png")!,
    "algo": URL(string: "https://coin-images.coingecko.com/coins/images/4380/large/download.png")!,
    "vet": URL(string: "https://coin-images.coingecko.com/coins/images/1167/large/VeChain-Logo-768x725.png")!,
    "ftm": URL(string: "https://coin-images.coingecko.com/coins/images/4001/large/Fantom_round.png")!,
    "egld": URL(string: "https://coin-images.coingecko.com/coins/images/12335/large/egld-token-logo.png")!,
    "aave": URL(string: "https://coin-images.coingecko.com/coins/images/12645/large/AAVE.png")!,
    "sand": URL(string: "https://coin-images.coingecko.com/coins/images/12129/large/sandbox_logo.jpg")!,
    "mana": URL(string: "https://coin-images.coingecko.com/coins/images/878/large/decentraland-mana.png")!,
    "grt": URL(string: "https://coin-images.coingecko.com/coins/images/13397/large/Graph_Token.png")!,
    "ape": URL(string: "https://coin-images.coingecko.com/coins/images/24383/large/apecoin.jpg")!,
    "crv": URL(string: "https://coin-images.coingecko.com/coins/images/12124/large/Curve.png")!,
    "ldo": URL(string: "https://coin-images.coingecko.com/coins/images/13573/large/Lido_DAO.png")!,
    "mkr": URL(string: "https://coin-images.coingecko.com/coins/images/1364/large/Mark_Maker.png")!,
    "snx": URL(string: "https://coin-images.coingecko.com/coins/images/3406/large/SNX.png")!,
    "comp": URL(string: "https://coin-images.coingecko.com/coins/images/10775/large/COMP.png")!,
    "1inch": URL(string: "https://coin-images.coingecko.com/coins/images/13469/large/1inch-token.png")!,
    "cake": URL(string: "https://coin-images.coingecko.com/coins/images/12632/large/pancakeswap-cake-logo.png")!,
    "pepe": URL(string: "https://coin-images.coingecko.com/coins/images/29850/large/pepe-token.jpeg")!,
    "wbtc": URL(string: "https://coin-images.coingecko.com/coins/images/7598/large/wrapped_bitcoin_wbtc.png")!,
    "dai": URL(string: "https://coin-images.coingecko.com/coins/images/9956/large/Badge_Dai.png")!,
    "busd": URL(string: "https://coin-images.coingecko.com/coins/images/9576/large/BUSD.png")!,
    "fdusd": URL(string: "https://coin-images.coingecko.com/coins/images/31079/large/firstdigitalusd.jpeg")!
]

private struct SymbolBadge: View {
    let symbol: String
    let color: Color
    let size: CGFloat
    var body: some View {
        let light = color.opacity(0.95)
        let dark  = color.opacity(0.55)
        ZStack {
            // Outer ring with subtle glow
            Circle()
                .fill(
                    RadialGradient(colors: [light.opacity(0.18), dark.opacity(0.08)], center: .center, startRadius: 2, endRadius: size * 0.7)
                )
                .overlay(
                    Circle().stroke(color.opacity(0.28), lineWidth: max(1, size * 0.04))
                )

            // Inner glossy disc
            Circle()
                .inset(by: size * 0.08)
                .fill(
                    LinearGradient(colors: [light.opacity(0.55), dark.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(
                    Circle()
                        .inset(by: size * 0.08)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .overlay(
                    // Specular highlight
                    Circle()
                        .inset(by: size * 0.16)
                        .trim(from: 0.0, to: 0.45)
                        .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: size * 0.06, lineCap: .round))
                        .rotationEffect(.degrees(-30))
                )

            // Symbol letters
            Text(String(symbol.prefix(3)).uppercased())
                .font(.system(size: size * 0.34, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
    }
}

/// Stock icon colors for well-known companies
private let StockBrandColors: [String: Color] = [
    "AAPL": Color(red: 0.6, green: 0.6, blue: 0.6),     // Apple - silver/gray
    "TSLA": Color(red: 0.9, green: 0.2, blue: 0.2),     // Tesla - red
    "NVDA": Color(red: 0.47, green: 0.73, blue: 0.15),  // Nvidia - green
    "MSFT": Color(red: 0.0, green: 0.64, blue: 0.95),   // Microsoft - blue
    "GOOGL": Color(red: 0.26, green: 0.52, blue: 0.96), // Google - blue
    "GOOG": Color(red: 0.26, green: 0.52, blue: 0.96),  // Google - blue
    "AMZN": Color(red: 1.0, green: 0.6, blue: 0.0),     // Amazon - orange
    "META": Color(red: 0.06, green: 0.52, blue: 0.99),  // Meta - blue
    "NFLX": Color(red: 0.89, green: 0.07, blue: 0.14),  // Netflix - red
    "AMD": Color(red: 0.0, green: 0.53, blue: 0.53),    // AMD - teal
    "INTC": Color(red: 0.0, green: 0.44, blue: 0.74),   // Intel - blue
    "CRM": Color(red: 0.0, green: 0.63, blue: 0.89),    // Salesforce - blue
    "PYPL": Color(red: 0.0, green: 0.19, blue: 0.56),   // PayPal - dark blue
    "SQ": Color(red: 0.0, green: 0.82, blue: 0.47),     // Block/Square - green
    "COIN": Color(red: 0.0, green: 0.35, blue: 0.97),   // Coinbase - blue
    "HOOD": Color(red: 0.0, green: 0.82, blue: 0.47),   // Robinhood - green
    "VOO": Color(red: 0.58, green: 0.11, blue: 0.11),   // Vanguard - maroon
    "SPY": Color(red: 0.0, green: 0.33, blue: 0.25),    // SPDR - dark green
    "QQQ": Color(red: 0.0, green: 0.35, blue: 0.65),    // Invesco - blue
    "VTI": Color(red: 0.58, green: 0.11, blue: 0.11),   // Vanguard - maroon
    "IWM": Color(red: 0.0, green: 0.0, blue: 0.0),      // iShares - black
    "DIA": Color(red: 0.0, green: 0.33, blue: 0.25),    // SPDR - dark green
]

/// Stock icon badge (similar to SymbolBadge but for stocks)
private struct StockIconBadge: View {
    let ticker: String
    let assetType: AssetType
    let size: CGFloat
    
    private var brandColor: Color {
        StockBrandColors[ticker.uppercased()] ?? assetType.color
    }
    
    var body: some View {
        let light = brandColor.opacity(0.95)
        let dark = brandColor.opacity(0.55)
        
        ZStack {
            // Background circle with gradient
            Circle()
                .fill(
                    LinearGradient(
                        colors: [light.opacity(0.3), dark.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Circle().stroke(brandColor.opacity(0.4), lineWidth: 1)
                )
            
            // Inner content
            if assetType == .etf {
                // ETF uses a chart icon
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundColor(brandColor)
            } else if assetType == .commodity {
                // Commodity uses distinctive CommodityIconView
                CommodityIconView(commodityId: ticker.lowercased(), size: size * 0.75)
            } else {
                // Stock uses ticker letters
                Text(String(ticker.prefix(4)).uppercased())
                    .font(.system(size: size * (ticker.count > 3 ? 0.26 : 0.32), weight: .heavy, design: .rounded))
                    .foregroundColor(brandColor)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(width: size, height: size)
    }
}

struct PortfolioCoinRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isExpanded: Bool = false
    @State private var cachedImageURL: URL? = nil
    @State private var hasInitializedURL: Bool = false
    @ObservedObject var viewModel: PortfolioViewModel
    let holding: Holding
    @AppStorage("hideBalances") private var hideBalances: Bool = false
    
    /// Optional callback when user taps to navigate to detail view
    /// For stocks: navigates to StockDetailView
    /// For crypto: navigates to CoinDetailView (handled by parent)
    var onNavigateToDetail: ((Holding) -> Void)?
    
    // MARK: - Asset Type Helpers
    
    /// Whether this holding is a stock, ETF, or commodity (not crypto)
    private var isSecuritiesHolding: Bool {
        holding.assetType == .stock || holding.assetType == .etf || holding.assetType == .commodity
    }
    
    // MARK: - Formatting Helpers
    
    /// Format quantity with appropriate precision
    private func formatQuantity(_ qty: Double) -> String {
        if qty >= 10000 {
            return String(format: "%.1f", qty)
        } else if qty >= 1000 {
            return String(format: "%.2f", qty)
        } else if qty >= 1 {
            return String(format: "%.4f", qty)
        } else if qty >= 0.0001 {
            return String(format: "%.6f", qty)
        } else {
            return String(format: "%.8f", qty)
        }
    }
    
    /// Stable image URL that doesn't change on re-renders
    private var stableImageURL: URL {
        // Return cached URL if available
        if let cached = cachedImageURL {
            return cached
        }
        // Compute URL (will be cached in onAppear)
        return computeImageURL()
    }
    
    /// Compute the best image URL with fallback chain
    private func computeImageURL() -> URL {
        let lower = holding.coinSymbol.lowercased()
        let providedURL: URL? = holding.imageUrl.flatMap { URL(string: $0) }
        let marketURL: URL? = MarketViewModel.shared.allCoins.first(where: { $0.symbol.lowercased() == lower })?.imageUrl
        let knownFallback: URL? = CoinIconFallbacks[lower]
        // CoinCap CDN is reliable and works for most coins
        let genericCDN: URL = URL(string: "https://assets.coincap.io/assets/icons/\(lower)@2x.png")!
        return providedURL ?? marketURL ?? knownFallback ?? genericCDN
    }
    
    /// Format price with proper currency formatting (commas + appropriate decimals)
    private func formatPrice(_ price: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = CurrencyManager.currencyCode
        if price >= 1_000_000 {
            // Compact: $1.2M
            let sym = CurrencyManager.symbol
            return String(format: "%@%.1fM", sym, price / 1_000_000)
        } else if price >= 1 {
            formatter.maximumFractionDigits = 2
            formatter.minimumFractionDigits = 2
        } else if price >= 0.01 {
            formatter.maximumFractionDigits = 4
            formatter.minimumFractionDigits = 2
        } else {
            formatter.maximumFractionDigits = 6
            formatter.minimumFractionDigits = 4
        }
        return formatter.string(from: NSNumber(value: price)) ?? String(format: "%@%.2f", CurrencyManager.symbol, price)
    }

    var body: some View {
        let total = viewModel.totalValue
        let allocationPercent: Double = total > 0 ? (holding.currentValue / total * 100) : 0
        let plDollar: Double = holding.profitLoss
        let cost: Double = holding.costBasis * holding.quantity
        let plPercent: Double = cost > 0 ? ((holding.currentValue - cost) / cost * 100) : 0
        let accent = viewModel.color(for: holding.displaySymbol)

        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 11) {
                // Icon: Stock logo for securities, coin image for crypto
                if isSecuritiesHolding {
                    StockImageView(
                        ticker: holding.displaySymbol,
                        assetType: holding.assetType,
                        size: 30
                    )
                    .overlay(Circle().stroke(accent.opacity(0.25), lineWidth: 1))
                } else {
                    // Use stable cached URL to prevent flashing on re-renders
                    CoinImageView(symbol: holding.coinSymbol, url: stableImageURL, size: 30)
                        .overlay(Circle().stroke(accent.opacity(0.25), lineWidth: 1))
                        .transaction { $0.disablesAnimations = true }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        // For commodities, show friendly name instead of raw ticker
                        // e.g., "Gold" instead of "Gold (GC=F)"
                        Text(holding.assetType == .commodity
                             ? holding.displayName
                             : "\(holding.displayName) (\(holding.displaySymbol))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                        
                        // Asset type badge for stocks/ETFs/commodities
                        if isSecuritiesHolding {
                            Text(holding.assetType.displayName.uppercased())
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(holding.assetType.color)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(holding.assetType.color.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 3))
                        }
                    }

                    HStack(spacing: 6) {
                        Image(systemName: holding.dailyChange >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.caption2.bold())
                            .foregroundColor(holding.dailyChange >= 0 ? .green : .red)
                        Text(String(format: isExpanded ? "24h: %.2f%%" : "%.2f%%", holding.dailyChange))
                            .font(.caption2)
                            .foregroundColor(holding.dailyChange >= 0 ? .green : .red)
                        Text(isExpanded ? "\(Int(allocationPercent.rounded()))% alloc" : "\(Int(allocationPercent.rounded()))%")
                            .font(.caption2)
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(
                                Capsule().fill(accent.opacity(0.12))
                            )
                            .overlay(
                                Capsule().stroke(accent.opacity(0.25), lineWidth: 0.5)
                            )
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .layoutPriority(0.5)
                    .allowsTightening(true)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Group {
                        if hideBalances {
                            Text("$••••••")
                        } else {
                            Text(holding.currentValue, format: .currency(code: CurrencyManager.currencyCode))
                        }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.25), value: holding.currentValue)
                    
                    Group {
                        if hideBalances {
                            Text("•••% • $••••")
                        } else {
                            Text(String(format: "%@%.2f%% • %@",
                                        plPercent >= 0 ? "+" : "",
                                        plPercent,
                                        PortfolioViewModel.signedCurrencyFormatter.string(from: NSNumber(value: plDollar)) ?? ""))
                        }
                    }
                    .font(.caption2)
                    .foregroundColor(plDollar >= 0 ? .green : .red)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .allowsTightening(true)
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.25), value: plDollar)
                }
                .layoutPriority(1)

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.bold())
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Collapse details" : "Expand details")
            }

            if isExpanded {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(DS.Adaptive.overlay(0.06))
                        Capsule()
                            .fill(LinearGradient(colors: [accent.opacity(0.9), accent.opacity(0.4)], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(4, geo.size.width * CGFloat(min(max(allocationPercent / 100.0, 0.0), 1.0))))
                    }
                }
                .frame(height: 3)
                .animation(.easeOut(duration: 0.35), value: allocationPercent)
            }

            if isExpanded {
                let avg = holding.costBasis
                let qty = holding.quantity
                let costTotal = avg * qty
                let price = holding.currentPrice
                let hasCostBasis = avg > 0
                
                // Compact grid layout that fits without horizontal scrolling
                HStack(spacing: 0) {
                    // Spacer to align with icon
                    Color.clear.frame(width: 41)
                    
                    // Three equal columns - show different data based on whether we have cost basis
                    HStack(spacing: 8) {
                        // Quantity/Shares - always shown
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isSecuritiesHolding ? "SHARES" : "QTY")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(DS.Adaptive.textTertiary)
                            Text(hideBalances ? "••••••" : (isSecuritiesHolding ? String(format: "%.2f", qty) : formatQuantity(qty)))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(DS.Adaptive.textPrimary.opacity(0.9))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // Current Price per coin
                        VStack(alignment: .leading, spacing: 2) {
                            Text("PRICE")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(DS.Adaptive.textTertiary)
                            Text(hideBalances ? "$••••" : formatPrice(price))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(DS.Adaptive.textPrimary.opacity(0.9))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        // Cost basis (if available) or Value (for Paper Trading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(hasCostBasis ? "COST" : "VALUE")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(DS.Adaptive.textTertiary)
                            Text(hideBalances ? "$••••" : formatPrice(hasCostBasis ? costTotal : holding.currentValue))
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(DS.Adaptive.textPrimary.opacity(0.9))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 4)
                .padding(.bottom, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 11))
        .onTapGesture {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                isExpanded.toggle()
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 11)
        .background(
            LinearGradient(
                colors: [
                    (plDollar >= 0 ? Color.green : Color.red).opacity(colorScheme == .dark ? 0.10 : 0.08),
                    DS.Adaptive.overlay(0.04)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: 11))
        )
        .id(holding.coinSymbol.uppercased())
        .animation(nil, value: holding.currentValue)
        .animation(nil, value: holding.dailyChange)
        .onAppear {
            // Cache the image URL once on first appear to prevent re-computation flashing
            if !hasInitializedURL {
                cachedImageURL = computeImageURL()
                hasInitializedURL = true
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // Delete action (especially useful in demo mode)
            Button(role: .destructive) {
                if let index = viewModel.holdings.firstIndex(where: { $0.id == holding.id }) {
                    viewModel.holdings.remove(at: index)
                }
            } label: { Label("Delete", systemImage: "trash") }
            
            Button {
                // TODO: Navigate to TradeView for this symbol
            } label: { Label("Trade", systemImage: "arrow.left.arrow.right") }
            .tint(Color.gold)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            // View Details action
            Button {
                onNavigateToDetail?(holding)
            } label: { Label("Details", systemImage: "chart.line.uptrend.xyaxis") }
            .tint(isSecuritiesHolding ? .blue : .orange)
        }
        // NOTE: Context menu is applied by PortfolioView to avoid conflicts
        .accessibilityHint("Swipe for actions like Add Transaction and Trade")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Toggle details")) {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                isExpanded.toggle()
            }
        }
    }
}

struct PortfolioCoinRow_Previews: PreviewProvider {
    static var previews: some View {
        let viewModel = PortfolioViewModel.sample
        let sampleHolding = Holding(
            id: UUID(),
            coinName: "Bitcoin",
            coinSymbol: "BTC",
            quantity: 1.0,
            currentPrice: 30000,
            costBasis: 25000,
            imageUrl: nil,
            isFavorite: true,
            dailyChange: 2.0,
            purchaseDate: Date()
        )
        PortfolioCoinRow(viewModel: viewModel, holding: sampleHolding)
            .previewLayout(.sizeThatFits)
    }
}

