//
//  CommodityIconView.swift
//  CryptoSage
//
//  Created by CryptoSage on 1/30/26.
//  Dedicated view for rendering distinctive commodity icons.
//  Supports custom assets with fallback to enhanced styled icons.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Commodity Icon View

/// A view that displays distinctive icons for commodities.
/// First attempts to load custom asset images, then falls back to enhanced styled icons.
struct CommodityIconView: View {
    let commodityId: String
    let size: CGFloat
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var assetImage: UIImage? = nil
    @State private var hasAttemptedLoad: Bool = false
    
    private var isDark: Bool { colorScheme == .dark }
    
    // Get commodity info from the symbol mapper
    private var commodityInfo: CommodityInfo? {
        CommoditySymbolMapper.getCommodity(for: commodityId) ??
        CommoditySymbolMapper.getCommodityById(commodityId)
    }
    
    // Commodity type for styling
    private var commodityType: CommodityType {
        commodityInfo?.type ?? CommoditySymbolMapper.commodityType(for: commodityId) ?? .preciousMetal
    }
    
    // Normalized commodity ID for lookups
    private var normalizedId: String {
        commodityInfo?.id ?? commodityId.lowercased()
    }
    
    var body: some View {
        ZStack {
            // Background circle with gradient
            Circle()
                .fill(backgroundGradient)
            
            // Glassmorphism overlay
            Circle()
                .fill(DS.Adaptive.chipBackground)
                .opacity(isDark ? 0.4 : 0.5)
            
            // Inner glow ring
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            iconColor.opacity(isDark ? 0.6 : 0.45),
                            iconColor.opacity(isDark ? 0.25 : 0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: size > 40 ? 2 : 1.5
                )
                .padding(2)
            
            // Icon content
            if let image = assetImage {
                // Custom asset image loaded
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size * 0.55, height: size * 0.55)
            } else {
                // Enhanced styled icon based on commodity
                commodityIconContent
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .onAppear {
            loadAssetImageIfNeeded()
        }
    }
    
    // MARK: - Background Gradient
    
    private var backgroundGradient: RadialGradient {
        RadialGradient(
            colors: [
                iconColor.opacity(isDark ? 0.45 : 0.35),
                iconColor.opacity(isDark ? 0.20 : 0.12),
                iconColor.opacity(isDark ? 0.10 : 0.05)
            ],
            center: .topLeading,
            startRadius: 0,
            endRadius: size * 0.9
        )
    }
    
    // MARK: - Icon Color
    
    private var iconColor: Color {
        switch commodityType {
        case .preciousMetal:
            // Gold-specific or silver-specific colors
            switch normalizedId {
            case "gold": return Color(red: 0.85, green: 0.65, blue: 0.13) // Gold
            case "silver": return Color(red: 0.75, green: 0.75, blue: 0.75) // Silver
            case "platinum": return Color(red: 0.90, green: 0.90, blue: 0.90) // Platinum
            case "palladium": return Color(red: 0.70, green: 0.70, blue: 0.75) // Palladium
            case "rhodium": return Color(red: 0.80, green: 0.80, blue: 0.85) // Rhodium - bright silver-blue
            case "iridium": return Color(red: 0.72, green: 0.72, blue: 0.80) // Iridium - blue-silver
            case "ruthenium": return Color(red: 0.65, green: 0.65, blue: 0.70) // Ruthenium - dark silver
            default: return Color.yellow
            }
        case .industrialMetal:
            switch normalizedId {
            case "copper": return Color(red: 0.72, green: 0.45, blue: 0.20) // Copper
            case "aluminum": return Color(red: 0.77, green: 0.77, blue: 0.77) // Aluminum
            case "zinc": return Color(red: 0.65, green: 0.68, blue: 0.72) // Zinc - blue-gray
            case "nickel": return Color(red: 0.75, green: 0.78, blue: 0.75) // Nickel - green-silver
            case "steel": return Color(red: 0.55, green: 0.55, blue: 0.60) // Steel - dark gray
            case "uranium": return Color(red: 0.30, green: 0.80, blue: 0.30) // Uranium - radioactive green
            default: return Color.orange
            }
        case .energy:
            switch normalizedId {
            case "crude_oil", "brent_oil": return Color(red: 0.15, green: 0.15, blue: 0.15) // Oil - dark
            case "natural_gas": return Color(red: 0.2, green: 0.5, blue: 0.9) // Gas - blue
            case "ethanol": return Color(red: 0.3, green: 0.7, blue: 0.3) // Ethanol - green
            default: return Color.blue
            }
        case .agriculture:
            switch normalizedId {
            case "corn": return Color(red: 0.95, green: 0.85, blue: 0.30) // Corn - yellow
            case "wheat": return Color(red: 0.85, green: 0.65, blue: 0.30) // Wheat - tan
            case "soybeans": return Color(red: 0.65, green: 0.75, blue: 0.35) // Soybeans - green
            case "coffee": return Color(red: 0.45, green: 0.30, blue: 0.15) // Coffee - brown
            case "cocoa": return Color(red: 0.35, green: 0.20, blue: 0.10) // Cocoa - dark brown
            case "cotton": return Color(red: 0.95, green: 0.95, blue: 0.95) // Cotton - white
            case "sugar": return Color(red: 0.95, green: 0.95, blue: 0.90) // Sugar - off-white
            case "oats": return Color(red: 0.85, green: 0.78, blue: 0.55) // Oats - light tan
            case "rice": return Color(red: 0.95, green: 0.93, blue: 0.85) // Rice - off-white
            case "orange_juice": return Color(red: 1.0, green: 0.65, blue: 0.0) // OJ - orange
            case "lumber": return Color(red: 0.55, green: 0.35, blue: 0.15) // Lumber - wood brown
            default: return Color.green
            }
        case .livestock:
            switch normalizedId {
            case "feeder_cattle": return Color(red: 0.55, green: 0.35, blue: 0.20) // Darker brown
            default: return Color(red: 0.60, green: 0.40, blue: 0.25) // Brown
            }
        }
    }
    
    // MARK: - Commodity Icon Content
    
    @ViewBuilder
    private var commodityIconContent: some View {
        switch normalizedId {
        // Precious Metals - use distinctive visual elements
        case "gold":
            goldBarIcon
        case "silver":
            silverCoinIcon
        case "platinum":
            platinumIngotIcon
        case "palladium":
            metalBarIcon(color: iconColor)
        case "rhodium":
            elementSymbolIcon(symbol: "Rh", color: iconColor)
        case "iridium":
            elementSymbolIcon(symbol: "Ir", color: iconColor)
        case "ruthenium":
            elementSymbolIcon(symbol: "Ru", color: iconColor)
            
        // Industrial Metals
        case "copper":
            copperIcon
        case "aluminum":
            metalBarIcon(color: iconColor)
        case "zinc":
            elementSymbolIcon(symbol: "Zn", color: iconColor)
        case "nickel":
            elementSymbolIcon(symbol: "Ni", color: iconColor)
        case "steel":
            steelIcon
        case "uranium":
            uraniumIcon
            
        // Energy
        case "crude_oil", "brent_oil":
            oilBarrelIcon
        case "natural_gas":
            gasFlameIcon
        case "heating_oil":
            fuelIcon
        case "gasoline":
            gasIcon
        case "ethanol":
            ethanolIcon
            
        // Agriculture
        case "corn":
            cornIcon
        case "wheat":
            wheatIcon
        case "soybeans":
            soybeanIcon
        case "coffee":
            coffeeIcon
        case "cocoa":
            cocoaIcon
        case "cotton":
            cottonIcon
        case "sugar":
            sugarIcon
        case "oats":
            oatsIcon
        case "rice":
            riceIcon
        case "orange_juice":
            orangeJuiceIcon
        case "lumber":
            lumberIcon
            
        // Livestock
        case "live_cattle", "feeder_cattle":
            cattleIcon
        case "lean_hogs":
            hogIcon
            
        // Default fallback
        default:
            defaultCommodityIcon
        }
    }
    
    // MARK: - Precious Metals Icons
    
    private var goldBarIcon: some View {
        ZStack {
            // Gold bar shape - trapezoid-like
            RoundedRectangle(cornerRadius: size * 0.06)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.85, blue: 0.35),
                            Color(red: 0.85, green: 0.65, blue: 0.13),
                            Color(red: 0.70, green: 0.50, blue: 0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.50, height: size * 0.30)
            
            // Shine effect
            RoundedRectangle(cornerRadius: size * 0.04)
                .fill(Color.white.opacity(0.4))
                .frame(width: size * 0.15, height: size * 0.08)
                .offset(x: -size * 0.12, y: -size * 0.06)
        }
    }
    
    private var silverCoinIcon: some View {
        ZStack {
            // Coin base
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.90, green: 0.90, blue: 0.92),
                            Color(red: 0.75, green: 0.75, blue: 0.78),
                            Color(red: 0.60, green: 0.60, blue: 0.65)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.50, height: size * 0.50)
            
            // Inner ring
            Circle()
                .stroke(Color.white.opacity(0.5), lineWidth: size * 0.02)
                .frame(width: size * 0.40, height: size * 0.40)
            
            // Dollar sign or Ag symbol
            Text("Ag")
                .font(.system(size: size * 0.16, weight: .bold, design: .serif))
                .foregroundColor(Color(red: 0.45, green: 0.45, blue: 0.50))
        }
    }
    
    private var platinumIngotIcon: some View {
        ZStack {
            // Ingot shape
            RoundedRectangle(cornerRadius: size * 0.04)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.95, green: 0.95, blue: 0.97),
                            Color(red: 0.85, green: 0.85, blue: 0.88),
                            Color(red: 0.70, green: 0.70, blue: 0.75)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.45, height: size * 0.35)
            
            // Pt symbol
            Text("Pt")
                .font(.system(size: size * 0.14, weight: .bold, design: .serif))
                .foregroundColor(Color(red: 0.50, green: 0.50, blue: 0.55))
        }
    }
    
    private func metalBarIcon(color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.06)
                .fill(
                    LinearGradient(
                        colors: [
                            color.opacity(0.9),
                            color,
                            color.opacity(0.7)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.50, height: size * 0.30)
        }
    }
    
    // MARK: - Industrial Metals Icons
    
    private var copperIcon: some View {
        ZStack {
            // Copper wire coil representation
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.80, green: 0.50, blue: 0.20),
                            Color(red: 0.72, green: 0.45, blue: 0.20),
                            Color(red: 0.55, green: 0.35, blue: 0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: size * 0.08
                )
                .frame(width: size * 0.40, height: size * 0.40)
            
            // Inner circle
            Circle()
                .fill(iconColor.opacity(0.3))
                .frame(width: size * 0.20, height: size * 0.20)
            
            Text("Cu")
                .font(.system(size: size * 0.12, weight: .bold, design: .serif))
                .foregroundColor(Color(red: 0.50, green: 0.30, blue: 0.10))
        }
    }
    
    // MARK: - Energy Icons
    
    private var oilBarrelIcon: some View {
        ZStack {
            // Barrel body
            RoundedRectangle(cornerRadius: size * 0.08)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.25, green: 0.25, blue: 0.25),
                            Color(red: 0.15, green: 0.15, blue: 0.15),
                            Color(red: 0.10, green: 0.10, blue: 0.10)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: size * 0.40, height: size * 0.50)
            
            // Barrel bands
            VStack(spacing: size * 0.12) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.gray.opacity(0.6))
                    .frame(width: size * 0.42, height: size * 0.03)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.gray.opacity(0.6))
                    .frame(width: size * 0.42, height: size * 0.03)
            }
            
            // Oil drop symbol
            Image(systemName: "drop.fill")
                .font(.system(size: size * 0.14))
                .foregroundColor(Color(red: 0.2, green: 0.2, blue: 0.3))
        }
    }
    
    private var gasFlameIcon: some View {
        ZStack {
            // Flame
            Image(systemName: "flame.fill")
                .font(.system(size: size * 0.40, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.3, green: 0.6, blue: 1.0),
                            Color(red: 0.2, green: 0.4, blue: 0.9),
                            Color(red: 0.1, green: 0.2, blue: 0.7)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }
    
    private var fuelIcon: some View {
        Image(systemName: "fuelpump.fill")
            .font(.system(size: size * 0.35, weight: .medium))
            .foregroundStyle(
                LinearGradient(
                    colors: [iconColor, iconColor.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }
    
    private var gasIcon: some View {
        Image(systemName: "car.fill")
            .font(.system(size: size * 0.32, weight: .medium))
            .foregroundStyle(
                LinearGradient(
                    colors: [iconColor, iconColor.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }
    
    // MARK: - Agriculture Icons
    
    private var cornIcon: some View {
        ZStack {
            // Corn cob representation
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.0, green: 0.90, blue: 0.35),
                            Color(red: 0.95, green: 0.80, blue: 0.25),
                            Color(red: 0.85, green: 0.70, blue: 0.20)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 0.25, height: size * 0.45)
            
            // Corn kernel dots
            VStack(spacing: size * 0.04) {
                ForEach(0..<4, id: \.self) { row in
                    HStack(spacing: size * 0.03) {
                        ForEach(0..<2, id: \.self) { _ in
                            Circle()
                                .fill(Color(red: 0.95, green: 0.85, blue: 0.30).opacity(0.5))
                                .frame(width: size * 0.04, height: size * 0.04)
                        }
                    }
                }
            }
        }
    }
    
    private var wheatIcon: some View {
        ZStack {
            // Wheat stalk representation using SF Symbol
            Image(systemName: "leaf.fill")
                .font(.system(size: size * 0.40, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.90, green: 0.75, blue: 0.35),
                            Color(red: 0.75, green: 0.55, blue: 0.25)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .rotationEffect(.degrees(-45))
        }
    }
    
    private var soybeanIcon: some View {
        ZStack {
            // Bean shape
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.75, green: 0.80, blue: 0.40),
                            Color(red: 0.55, green: 0.65, blue: 0.30)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.35, height: size * 0.22)
                .rotationEffect(.degrees(-20))
            
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.70, green: 0.75, blue: 0.35),
                            Color(red: 0.50, green: 0.60, blue: 0.25)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.30, height: size * 0.18)
                .offset(x: size * 0.08, y: size * 0.10)
                .rotationEffect(.degrees(15))
        }
    }
    
    private var coffeeIcon: some View {
        ZStack {
            // Coffee cup
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: size * 0.38, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.55, green: 0.35, blue: 0.20),
                            Color(red: 0.35, green: 0.20, blue: 0.10)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }
    
    private var cocoaIcon: some View {
        ZStack {
            // Cocoa bean representation
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.45, green: 0.28, blue: 0.15),
                            Color(red: 0.30, green: 0.18, blue: 0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.40, height: size * 0.25)
                .rotationEffect(.degrees(-10))
        }
    }
    
    private var cottonIcon: some View {
        ZStack {
            // Cotton boll - fluffy cloud-like
            ForEach(0..<5, id: \.self) { i in
                Circle()
                    .fill(Color.white)
                    .frame(width: size * 0.20, height: size * 0.20)
                    .offset(
                        x: CGFloat(cos(Double(i) * .pi * 2 / 5)) * size * 0.12,
                        y: CGFloat(sin(Double(i) * .pi * 2 / 5)) * size * 0.12
                    )
            }
            Circle()
                .fill(Color.white)
                .frame(width: size * 0.22, height: size * 0.22)
        }
    }
    
    private var sugarIcon: some View {
        ZStack {
            // Sugar cube representation
            RoundedRectangle(cornerRadius: size * 0.04)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white,
                            Color(red: 0.95, green: 0.95, blue: 0.90)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.35, height: size * 0.35)
            
            // Sparkle
            Image(systemName: "sparkle")
                .font(.system(size: size * 0.12))
                .foregroundColor(Color.gray.opacity(0.3))
        }
    }
    
    // MARK: - Livestock Icons
    
    private var cattleIcon: some View {
        Image(systemName: "hare.fill") // Using hare as placeholder, ideally would be cattle
            .font(.system(size: size * 0.35, weight: .medium))
            .foregroundStyle(
                LinearGradient(
                    colors: [iconColor, iconColor.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }
    
    private var hogIcon: some View {
        Image(systemName: "hare.fill")
            .font(.system(size: size * 0.35, weight: .medium))
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.95, green: 0.75, blue: 0.75),
                        Color(red: 0.85, green: 0.60, blue: 0.60)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }
    
    // MARK: - Element Symbol Icon (for metals like Rh, Ir, Ru, Zn, Ni)
    
    private func elementSymbolIcon(symbol: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.06)
                .fill(
                    LinearGradient(
                        colors: [
                            color.opacity(0.9),
                            color,
                            color.opacity(0.7)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.50, height: size * 0.35)
            
            Text(symbol)
                .font(.system(size: size * 0.15, weight: .bold, design: .serif))
                .foregroundColor(isDark ? Color.black.opacity(0.6) : Color.white.opacity(0.9))
        }
    }
    
    // MARK: - New Industrial Metal Icons
    
    private var steelIcon: some View {
        ZStack {
            // I-beam shape using rectangles
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.65, green: 0.65, blue: 0.70),
                            Color(red: 0.50, green: 0.50, blue: 0.55),
                            Color(red: 0.40, green: 0.40, blue: 0.45)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 0.45, height: size * 0.08)
                .offset(y: -size * 0.14)
            
            Rectangle()
                .fill(Color(red: 0.55, green: 0.55, blue: 0.60))
                .frame(width: size * 0.12, height: size * 0.36)
            
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.55, green: 0.55, blue: 0.60),
                            Color(red: 0.40, green: 0.40, blue: 0.45)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size * 0.45, height: size * 0.08)
                .offset(y: size * 0.14)
        }
    }
    
    private var uraniumIcon: some View {
        ZStack {
            // Radiation symbol
            Image(systemName: "atom")
                .font(.system(size: size * 0.40, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.2, green: 0.9, blue: 0.2),
                            Color(red: 0.1, green: 0.7, blue: 0.1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }
    
    // MARK: - New Energy Icons
    
    private var ethanolIcon: some View {
        ZStack {
            Image(systemName: "leaf.circle.fill")
                .font(.system(size: size * 0.40, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.3, green: 0.8, blue: 0.3),
                            Color(red: 0.2, green: 0.6, blue: 0.2)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }
    
    // MARK: - New Agriculture Icons
    
    private var oatsIcon: some View {
        ZStack {
            Image(systemName: "leaf.fill")
                .font(.system(size: size * 0.38, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.90, green: 0.82, blue: 0.60),
                            Color(red: 0.75, green: 0.65, blue: 0.40)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
    }
    
    private var riceIcon: some View {
        ZStack {
            // Rice grain shapes
            VStack(spacing: size * 0.02) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(Color.white)
                        .frame(width: size * 0.30, height: size * 0.10)
                        .rotationEffect(.degrees(Double(i - 1) * 10))
                        .offset(x: CGFloat(i - 1) * size * 0.03)
                }
            }
        }
    }
    
    private var orangeJuiceIcon: some View {
        ZStack {
            // Orange circle
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 1.0, green: 0.70, blue: 0.05),
                            Color(red: 1.0, green: 0.55, blue: 0.0)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.25
                    )
                )
                .frame(width: size * 0.42, height: size * 0.42)
            
            // Leaf
            Image(systemName: "leaf.fill")
                .font(.system(size: size * 0.12))
                .foregroundColor(Color.green)
                .offset(x: size * 0.12, y: -size * 0.18)
        }
    }
    
    private var lumberIcon: some View {
        ZStack {
            // Log cross-section
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.75, green: 0.55, blue: 0.30),
                            Color(red: 0.55, green: 0.35, blue: 0.15),
                            Color(red: 0.40, green: 0.25, blue: 0.10)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.25
                    )
                )
                .frame(width: size * 0.45, height: size * 0.45)
            
            // Tree rings
            Circle()
                .stroke(Color(red: 0.65, green: 0.45, blue: 0.25).opacity(0.5), lineWidth: size * 0.015)
                .frame(width: size * 0.30, height: size * 0.30)
            Circle()
                .stroke(Color(red: 0.65, green: 0.45, blue: 0.25).opacity(0.5), lineWidth: size * 0.015)
                .frame(width: size * 0.18, height: size * 0.18)
            Circle()
                .fill(Color(red: 0.60, green: 0.40, blue: 0.20))
                .frame(width: size * 0.06, height: size * 0.06)
        }
    }
    
    // MARK: - Default Icon
    
    private var defaultCommodityIcon: some View {
        Image(systemName: "scalemass.fill")
            .font(.system(size: size * 0.35, weight: .medium))
            .foregroundStyle(
                LinearGradient(
                    colors: [iconColor, iconColor.opacity(0.7)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }
    
    // MARK: - Asset Loading
    
    private func loadAssetImageIfNeeded() {
        guard !hasAttemptedLoad else { return }
        hasAttemptedLoad = true
        
        // Try to load custom asset
        let assetName = "commodity_\(normalizedId)"
        if let image = UIImage(named: assetName) {
            assetImage = image
        }
    }
}

// MARK: - Preview

#Preview("All Commodities") {
    ScrollView {
        VStack(spacing: 24) {
            Text("Precious Metals")
                .font(.headline)
                .foregroundColor(.white)
            
            HStack(spacing: 16) {
                CommodityIconView(commodityId: "gold", size: 50)
                CommodityIconView(commodityId: "silver", size: 50)
                CommodityIconView(commodityId: "platinum", size: 50)
                CommodityIconView(commodityId: "palladium", size: 50)
            }
            
            Text("Industrial Metals")
                .font(.headline)
                .foregroundColor(.white)
            
            HStack(spacing: 16) {
                CommodityIconView(commodityId: "copper", size: 50)
                CommodityIconView(commodityId: "aluminum", size: 50)
            }
            
            Text("Energy")
                .font(.headline)
                .foregroundColor(.white)
            
            HStack(spacing: 16) {
                CommodityIconView(commodityId: "crude_oil", size: 50)
                CommodityIconView(commodityId: "natural_gas", size: 50)
                CommodityIconView(commodityId: "heating_oil", size: 50)
                CommodityIconView(commodityId: "gasoline", size: 50)
            }
            
            Text("Agriculture")
                .font(.headline)
                .foregroundColor(.white)
            
            HStack(spacing: 16) {
                CommodityIconView(commodityId: "corn", size: 50)
                CommodityIconView(commodityId: "wheat", size: 50)
                CommodityIconView(commodityId: "soybeans", size: 50)
                CommodityIconView(commodityId: "coffee", size: 50)
            }
            
            HStack(spacing: 16) {
                CommodityIconView(commodityId: "cocoa", size: 50)
                CommodityIconView(commodityId: "cotton", size: 50)
                CommodityIconView(commodityId: "sugar", size: 50)
            }
            
            Text("Livestock")
                .font(.headline)
                .foregroundColor(.white)
            
            HStack(spacing: 16) {
                CommodityIconView(commodityId: "live_cattle", size: 50)
                CommodityIconView(commodityId: "lean_hogs", size: 50)
            }
            
            Text("Size Variations")
                .font(.headline)
                .foregroundColor(.white)
            
            HStack(spacing: 16) {
                CommodityIconView(commodityId: "gold", size: 32)
                CommodityIconView(commodityId: "gold", size: 44)
                CommodityIconView(commodityId: "gold", size: 56)
                CommodityIconView(commodityId: "gold", size: 72)
            }
        }
        .padding()
    }
    .background(Color.black)
    .preferredColorScheme(.dark)
}
