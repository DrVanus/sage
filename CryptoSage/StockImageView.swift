//
//  StockImageView.swift
//  CryptoSage
//
//  Created by CryptoSage on 1/19/26.
//  SwiftUI view for displaying stock/ETF company logos with caching and fallback.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Stock Image View

/// A SwiftUI view that displays company logos for stocks and ETFs.
/// Uses multiple logo APIs with caching and falls back to a stylized ticker badge if unavailable.
struct StockImageView: View {
    let ticker: String
    let assetType: AssetType
    let size: CGFloat
    
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var loadedImage: StockPlatformImage? = nil
    @State private var isLoading: Bool = false
    @State private var hasAttemptedLoad: Bool = false
    @State private var shimmerPhase: CGFloat = 0
    
    private var isDark: Bool { colorScheme == .dark }
    
    /// Brand colors for well-known companies (expanded list)
    private static let brandColors: [String: Color] = [
        // Big Tech
        "AAPL": Color(red: 0.55, green: 0.55, blue: 0.55),   // Apple - silver
        "TSLA": Color(red: 0.9, green: 0.2, blue: 0.2),      // Tesla - red
        "NVDA": Color(red: 0.47, green: 0.73, blue: 0.15),   // Nvidia - green
        "MSFT": Color(red: 0.0, green: 0.64, blue: 0.95),    // Microsoft - blue
        "GOOGL": Color(red: 0.26, green: 0.52, blue: 0.96),  // Google - blue
        "GOOG": Color(red: 0.26, green: 0.52, blue: 0.96),
        "AMZN": Color(red: 1.0, green: 0.6, blue: 0.0),      // Amazon - orange
        "META": Color(red: 0.06, green: 0.52, blue: 0.99),   // Meta - blue
        "NFLX": Color(red: 0.89, green: 0.07, blue: 0.14),   // Netflix - red
        "AMD": Color(red: 0.0, green: 0.53, blue: 0.53),     // AMD - teal
        "INTC": Color(red: 0.0, green: 0.44, blue: 0.74),    // Intel - blue
        "ORCL": Color(red: 0.8, green: 0.0, blue: 0.0),      // Oracle - red
        "ADBE": Color(red: 0.98, green: 0.0, blue: 0.0),     // Adobe - red
        "CRM": Color(red: 0.0, green: 0.63, blue: 0.89),     // Salesforce - blue
        "CSCO": Color(red: 0.0, green: 0.54, blue: 0.73),    // Cisco - teal
        "IBM": Color(red: 0.0, green: 0.33, blue: 0.62),     // IBM - blue
        
        // Finance
        "PYPL": Color(red: 0.0, green: 0.19, blue: 0.56),    // PayPal - dark blue
        "SQ": Color(red: 0.0, green: 0.82, blue: 0.47),      // Block/Square - green
        "COIN": Color(red: 0.0, green: 0.35, blue: 0.97),    // Coinbase - blue
        "HOOD": Color(red: 0.0, green: 0.82, blue: 0.47),    // Robinhood - green
        "JPM": Color(red: 0.0, green: 0.24, blue: 0.53),     // JPMorgan - dark blue
        "V": Color(red: 0.1, green: 0.12, blue: 0.44),       // Visa - dark blue
        "MA": Color(red: 0.92, green: 0.0, blue: 0.1),       // Mastercard - red
        "BAC": Color(red: 0.0, green: 0.27, blue: 0.53),     // Bank of America - blue
        "GS": Color(red: 0.4, green: 0.55, blue: 0.75),      // Goldman Sachs - blue
        "MS": Color(red: 0.0, green: 0.29, blue: 0.53),      // Morgan Stanley - blue
        "AXP": Color(red: 0.0, green: 0.4, blue: 0.73),      // American Express - blue
        
        // Consumer
        "DIS": Color(red: 0.0, green: 0.44, blue: 0.65),     // Disney - blue
        "WMT": Color(red: 0.0, green: 0.47, blue: 0.76),     // Walmart - blue
        "HD": Color(red: 0.97, green: 0.47, blue: 0.13),     // Home Depot - orange
        "NKE": Color(red: 0.96, green: 0.45, blue: 0.0),     // Nike - orange (swoosh)
        "SBUX": Color(red: 0.0, green: 0.44, blue: 0.26),    // Starbucks - green
        "MCD": Color(red: 0.86, green: 0.14, blue: 0.14),    // McDonald's - red
        "KO": Color(red: 0.96, green: 0.15, blue: 0.15),     // Coca-Cola - red
        "PEP": Color(red: 0.0, green: 0.27, blue: 0.63),     // Pepsi - blue
        "COST": Color(red: 0.89, green: 0.11, blue: 0.17),   // Costco - red
        "TGT": Color(red: 0.8, green: 0.0, blue: 0.0),       // Target - red
        
        // Healthcare
        "JNJ": Color(red: 0.82, green: 0.04, blue: 0.16),    // J&J - red
        "PFE": Color(red: 0.0, green: 0.33, blue: 0.62),     // Pfizer - blue
        "UNH": Color(red: 0.0, green: 0.35, blue: 0.65),     // UnitedHealth - blue
        "MRNA": Color(red: 0.0, green: 0.55, blue: 0.8),     // Moderna - teal
        
        // Energy
        "XOM": Color(red: 0.92, green: 0.0, blue: 0.0),      // Exxon - red
        "CVX": Color(red: 0.0, green: 0.25, blue: 0.53),     // Chevron - blue
        
        // Automotive
        "F": Color(red: 0.0, green: 0.25, blue: 0.53),       // Ford - blue
        "GM": Color(red: 0.0, green: 0.33, blue: 0.62),      // GM - blue
        "RIVN": Color(red: 0.98, green: 0.65, blue: 0.0),    // Rivian - orange
        "LCID": Color(red: 0.75, green: 0.6, blue: 0.4),     // Lucid - gold
        
        // ETFs - Vanguard
        "VOO": Color(red: 0.58, green: 0.11, blue: 0.11),    // Vanguard - maroon
        "VTI": Color(red: 0.58, green: 0.11, blue: 0.11),
        "VTV": Color(red: 0.58, green: 0.11, blue: 0.11),
        "VUG": Color(red: 0.58, green: 0.11, blue: 0.11),
        "VGT": Color(red: 0.58, green: 0.11, blue: 0.11),
        "BND": Color(red: 0.58, green: 0.11, blue: 0.11),
        
        // ETFs - SPDR
        "SPY": Color(red: 0.0, green: 0.33, blue: 0.25),     // SPDR - dark green
        "DIA": Color(red: 0.0, green: 0.33, blue: 0.25),
        "GLD": Color(red: 0.85, green: 0.65, blue: 0.13),    // Gold ETF - gold
        "XLF": Color(red: 0.0, green: 0.33, blue: 0.25),
        "XLK": Color(red: 0.0, green: 0.33, blue: 0.25),
        
        // ETFs - iShares
        "IWM": Color(red: 0.0, green: 0.0, blue: 0.0),       // iShares - black
        "EEM": Color(red: 0.0, green: 0.0, blue: 0.0),
        "AGG": Color(red: 0.0, green: 0.0, blue: 0.0),
        "TLT": Color(red: 0.0, green: 0.0, blue: 0.0),
        
        // ETFs - Invesco
        "QQQ": Color(red: 0.0, green: 0.35, blue: 0.65),     // Invesco - blue
        "QQQM": Color(red: 0.0, green: 0.35, blue: 0.65),
        
        // ETFs - ARK
        "ARKK": Color(red: 0.95, green: 0.6, blue: 0.1),     // ARK - orange
        "ARKW": Color(red: 0.95, green: 0.6, blue: 0.1),
        "ARKG": Color(red: 0.95, green: 0.6, blue: 0.1),
        "ARKF": Color(red: 0.95, green: 0.6, blue: 0.1),
    ]
    
    private var brandColor: Color {
        // Check for commodity type first
        if assetType == .commodity {
            if let commodityType = CommoditySymbolMapper.commodityType(for: ticker) {
                switch commodityType {
                case .preciousMetal:
                    return Color.yellow
                case .industrialMetal:
                    return Color.orange
                case .energy:
                    return Color.blue
                case .agriculture:
                    return Color.green
                case .livestock:
                    return Color.brown
                }
            }
        }
        
        if let color = Self.brandColors[ticker.uppercased()] {
            return color
        }
        // Generate consistent color from ticker hash for unknown stocks
        return generateColorFromTicker(ticker)
    }
    
    /// Generate a consistent color based on ticker string
    private func generateColorFromTicker(_ ticker: String) -> Color {
        let hash = ticker.uppercased().unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let hue = Double(hash % 360) / 360.0
        let saturation = 0.55 + Double(hash % 30) / 100.0
        let brightness = 0.65 + Double(hash % 20) / 100.0
        return Color(hue: hue, saturation: saturation, brightness: brightness)
    }
    
    var body: some View {
        // Use dedicated CommodityIconView for commodities - distinctive visual icons
        if assetType == .commodity {
            CommodityIconView(
                commodityId: CommoditySymbolMapper.getCommodity(for: ticker)?.id ?? ticker,
                size: size
            )
        } else {
            // Standard stock/ETF logo handling
            ZStack {
                // Background circle
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                brandColor.opacity(isDark ? 0.20 : 0.14),
                                brandColor.opacity(isDark ? 0.08 : 0.05),
                                Color.clear
                            ],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: size * 0.9
                        )
                    )
                
                if let image = loadedImage {
                    // Successfully loaded logo with fade-in
                    ZStack {
                        // Contrast plate keeps dark favicons readable on dark cards.
                        Circle()
                            .fill(isDark ? Color.white.opacity(0.96) : Color.white.opacity(0.9))
                            .padding(size * 0.10)
                            .shadow(color: .black.opacity(isDark ? 0.22 : 0.08), radius: 2, x: 0, y: 1)
                        logoImageView(image)
                    }
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                } else if isLoading {
                    // Shimmer loading state
                    shimmerLoadingView
                } else {
                    // Premium fallback ticker badge
                    tickerBadge
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(
                        loadedImage != nil
                            ? (isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.12))
                            : Color.clear,  // Badge handles its own border
                        lineWidth: 1
                    )
            )
            .onAppear {
                loadLogoIfNeeded()
            }
            .task(id: ticker) {
                await loadLogo()
            }
        }
    }
    
    // MARK: - Logo Image View
    
    @ViewBuilder
    private func logoImageView(_ image: StockPlatformImage) -> some View {
        #if canImport(UIKit)
        Image(uiImage: image)
            .resizable()
            .renderingMode(.original)
            .scaledToFit()
            .frame(width: size * 0.66, height: size * 0.66)
            .clipShape(Circle())
        #elseif canImport(AppKit)
        Image(nsImage: image)
            .resizable()
            .renderingMode(.original)
            .scaledToFit()
            .frame(width: size * 0.66, height: size * 0.66)
            .clipShape(Circle())
        #endif
    }
    
    // MARK: - Shimmer Loading State
    
    private var shimmerLoadingView: some View {
        ZStack {
            // Base background
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            brandColor.opacity(0.15),
                            brandColor.opacity(0.08),
                            brandColor.opacity(0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Shimmer overlay
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.white.opacity(isDark ? 0.15 : 0.25),
                            Color.clear
                        ],
                        startPoint: UnitPoint(x: shimmerPhase - 0.3, y: shimmerPhase - 0.3),
                        endPoint: UnitPoint(x: shimmerPhase + 0.3, y: shimmerPhase + 0.3)
                    )
                )
                .onAppear {
                    withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                        shimmerPhase = 1.3
                    }
                }
            
            // Faint ticker while loading
            Text(String(ticker.prefix(2)).uppercased())
                .font(.system(size: size * 0.28, weight: .bold, design: .rounded))
                .foregroundColor(brandColor.opacity(0.3))
        }
    }
    
    // MARK: - Premium Ticker Badge Fallback
    
    private var tickerBadge: some View {
        ZStack {
            // Rich radial gradient background
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            brandColor.opacity(isDark ? 0.45 : 0.35),
                            brandColor.opacity(isDark ? 0.20 : 0.12),
                            brandColor.opacity(isDark ? 0.10 : 0.05)
                        ],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: size * 0.9
                    )
                )
            
            // Glassmorphism overlay for depth
            Circle()
                .fill(DS.Adaptive.chipBackground)
                .opacity(isDark ? 0.45 : 0.6)
            
            // Inner glow ring
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            brandColor.opacity(isDark ? 0.6 : 0.45),
                            brandColor.opacity(isDark ? 0.25 : 0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: size > 40 ? 2 : 1.5
                )
                .padding(2)
            
            // Secondary subtle inner ring for premium feel
            Circle()
                .stroke(
                    Color.white.opacity(isDark ? 0.08 : 0.15),
                    lineWidth: 0.5
                )
                .padding(4)
            
            // Content based on asset type
            if assetType == .etf {
                etfBadgeContent
            } else if assetType == .commodity {
                commodityBadgeContent
            } else {
                stockBadgeContent
            }
        }
        // Outer glow for depth
    }
    
    // MARK: - ETF Badge Content
    
    private var etfBadgeContent: some View {
        VStack(spacing: size >= 44 ? 2 : 0) {
            // Chart icon for ETFs with gradient
            Image(systemName: "chart.pie.fill")
                .font(.system(size: size * 0.32, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [brandColor, brandColor.opacity(0.75)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            // Show ticker below icon if space permits
            if size >= 40 {
                Text(String(ticker.prefix(3)).uppercased())
                    .font(.system(size: size * 0.16, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [brandColor.opacity(0.9), brandColor.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
    }
    
    // MARK: - Commodity Badge Content
    
    /// Get the icon and color for a commodity based on its type
    private var commodityIconInfo: (icon: String, color: Color) {
        // Try to get commodity type from CommoditySymbolMapper
        if let commodityType = CommoditySymbolMapper.commodityType(for: ticker) {
            switch commodityType {
            case .preciousMetal:
                return ("sparkles", Color.yellow)
            case .industrialMetal:
                return ("hammer.fill", Color.orange)
            case .energy:
                return ("flame.fill", Color.blue)
            case .agriculture:
                return ("leaf.fill", Color.green)
            case .livestock:
                return ("hare.fill", Color.brown)
            }
        }
        // Default fallback
        return ("scalemass.fill", brandColor)
    }
    
    private var commodityBadgeContent: some View {
        let iconInfo = commodityIconInfo
        
        return VStack(spacing: size >= 44 ? 2 : 0) {
            // Type-specific icon for commodities
            Image(systemName: iconInfo.icon)
                .font(.system(size: size * 0.32, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [iconInfo.color, iconInfo.color.opacity(0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            // Abbreviated name for larger sizes
            if size >= 44 {
                Text(String(ticker.replacingOccurrences(of: "=F", with: "").prefix(3)).uppercased())
                    .font(.system(size: size * 0.16, weight: .bold, design: .rounded))
                    .foregroundColor(iconInfo.color.opacity(0.9))
            }
        }
    }
    
    // MARK: - Stock Badge Content
    
    private var stockBadgeContent: some View {
        Text(String(ticker.prefix(4)).uppercased())
            .font(.system(size: tickerFontSize, weight: .black, design: .rounded))
            .foregroundStyle(
                LinearGradient(
                    colors: [brandColor, brandColor.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .minimumScaleFactor(0.5)
            .lineLimit(1)
    }
    
    private var tickerFontSize: CGFloat {
        let charCount = min(ticker.count, 4)
        switch charCount {
        case 1: return size * 0.48
        case 2: return size * 0.40
        case 3: return size * 0.32
        default: return size * 0.26
        }
    }
    
    // MARK: - Logo Loading
    
    private func loadLogoIfNeeded() {
        guard !hasAttemptedLoad else { return }
        
        // Check sync cache first
        if let cached = StockLogoService.shared.getCachedLogo(for: ticker) {
            loadedImage = cached
            hasAttemptedLoad = true
        }
    }
    
    private func loadLogo() async {
        guard loadedImage == nil, !isLoading else { return }
        
        await MainActor.run { isLoading = true }
        
        let image = await StockLogoService.shared.fetchLogo(for: ticker)
        
        await MainActor.run {
            isLoading = false
            hasAttemptedLoad = true
            if let image = image {
                withAnimation(.easeOut(duration: 0.16)) {
                    loadedImage = image
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Dark Mode") {
    VStack(spacing: 24) {
        Text("Popular Stocks")
            .font(.headline)
            .foregroundColor(.white)
        
        HStack(spacing: 16) {
            StockImageView(ticker: "AAPL", assetType: .stock, size: 50)
            StockImageView(ticker: "TSLA", assetType: .stock, size: 50)
            StockImageView(ticker: "NVDA", assetType: .stock, size: 50)
            StockImageView(ticker: "MSFT", assetType: .stock, size: 50)
        }
        
        Text("ETFs")
            .font(.headline)
            .foregroundColor(.white)
        
        HStack(spacing: 16) {
            StockImageView(ticker: "VOO", assetType: .etf, size: 50)
            StockImageView(ticker: "SPY", assetType: .etf, size: 50)
            StockImageView(ticker: "QQQ", assetType: .etf, size: 50)
            StockImageView(ticker: "ARKK", assetType: .etf, size: 50)
        }
        
        Text("Unknown/Generated Colors")
            .font(.headline)
            .foregroundColor(.white)
        
        HStack(spacing: 16) {
            StockImageView(ticker: "ACME", assetType: .stock, size: 50)
            StockImageView(ticker: "XYZ", assetType: .stock, size: 50)
            StockImageView(ticker: "TEST", assetType: .etf, size: 50)
            StockImageView(ticker: "NEW", assetType: .stock, size: 50)
        }
        
        Text("Size Variations")
            .font(.headline)
            .foregroundColor(.white)
        
        HStack(spacing: 16) {
            StockImageView(ticker: "AAPL", assetType: .stock, size: 32)
            StockImageView(ticker: "AAPL", assetType: .stock, size: 44)
            StockImageView(ticker: "AAPL", assetType: .stock, size: 56)
            StockImageView(ticker: "AAPL", assetType: .stock, size: 72)
        }
    }
    .padding()
    .background(Color.black)
    .preferredColorScheme(.dark)
}

#Preview("Light Mode") {
    VStack(spacing: 20) {
        HStack(spacing: 16) {
            StockImageView(ticker: "AAPL", assetType: .stock, size: 50)
            StockImageView(ticker: "TSLA", assetType: .stock, size: 50)
            StockImageView(ticker: "NVDA", assetType: .stock, size: 50)
            StockImageView(ticker: "MSFT", assetType: .stock, size: 50)
        }
        
        HStack(spacing: 16) {
            StockImageView(ticker: "VOO", assetType: .etf, size: 50)
            StockImageView(ticker: "SPY", assetType: .etf, size: 50)
            StockImageView(ticker: "QQQ", assetType: .etf, size: 50)
            StockImageView(ticker: "ARKK", assetType: .etf, size: 50)
        }
    }
    .padding()
    .background(Color.white)
    .preferredColorScheme(.light)
}

#Preview("Commodities") {
    VStack(spacing: 24) {
        Text("Precious Metals")
            .font(.headline)
            .foregroundColor(.white)
        
        HStack(spacing: 16) {
            StockImageView(ticker: "GC=F", assetType: .commodity, size: 50)
            StockImageView(ticker: "SI=F", assetType: .commodity, size: 50)
            StockImageView(ticker: "PL=F", assetType: .commodity, size: 50)
            StockImageView(ticker: "XAU", assetType: .commodity, size: 50)
        }
        
        Text("Energy")
            .font(.headline)
            .foregroundColor(.white)
        
        HStack(spacing: 16) {
            StockImageView(ticker: "CL=F", assetType: .commodity, size: 50)
            StockImageView(ticker: "NG=F", assetType: .commodity, size: 50)
            StockImageView(ticker: "BZ=F", assetType: .commodity, size: 50)
            StockImageView(ticker: "HO=F", assetType: .commodity, size: 50)
        }
        
        Text("Industrial & Agriculture")
            .font(.headline)
            .foregroundColor(.white)
        
        HStack(spacing: 16) {
            StockImageView(ticker: "HG=F", assetType: .commodity, size: 50)
            StockImageView(ticker: "ZC=F", assetType: .commodity, size: 50)
            StockImageView(ticker: "ZW=F", assetType: .commodity, size: 50)
            StockImageView(ticker: "KC=F", assetType: .commodity, size: 50)
        }
    }
    .padding()
    .background(Color.black)
    .preferredColorScheme(.dark)
}
