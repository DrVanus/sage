import SwiftUI

// MARK: - Coin Info Card shown when a tile is focused
struct HeatMapInfoBar: View {
    let tile: HeatMapTile
    let timeframe: HeatMapTimeframe
    let changeProvider: ((HeatMapTile) -> Double)?
    var onClose: () -> Void
    var onViewDetails: () -> Void
    var onViewOthers: (() -> Void)? = nil
    
    // Cache coin data to prevent mismatch during view updates
    @State private var cachedSymbol: String = ""
    @State private var cachedCoinID: String = ""
    @State private var cachedName: String = ""
    @State private var cachedImageURL: URL? = nil
    @State private var cachedPrice: Double? = nil
    @State private var cachedRank: Int? = nil
    @State private var cachedMarketCap: Double? = nil
    @State private var cachedVolume: Double? = nil
    @State private var cached1hChange: Double? = nil
    @State private var cached24hChange: Double? = nil
    @State private var cached7dChange: Double? = nil
    
    private func updateCachedCoinData() {
        let symbol = tile.symbol.uppercased()
        cachedSymbol = symbol
        
        if let coin = MarketViewModel.shared.allCoins.first(where: { $0.symbol.uppercased() == symbol }) {
            cachedCoinID = coin.id
            cachedName = coin.name
            cachedImageURL = coin.imageUrl
            // PRICE CONSISTENCY FIX: Use bestPrice() for consistent pricing across all views
            // bestPrice() checks LivePriceManager.currentCoinsList for the freshest data
            cachedPrice = MarketViewModel.shared.bestPrice(for: coin.id) ?? coin.priceUsd
            cachedRank = coin.marketCapRank
            cachedMarketCap = coin.marketCap
            cachedVolume = coin.totalVolume
            // HEAT MAP CONSISTENCY FIX: Use tile's percentage values to match the heat map display
            // Previously used LivePriceManager which had different (fresher) data, causing
            // the info bar to show different percentages than the tile (e.g. 0.9% vs 0.6%)
            // Now both the tile and info bar show the same values from the same data source
            cached1hChange = tile.pctChange1h
            cached24hChange = tile.pctChange24h
            cached7dChange = tile.pctChange7d
        } else {
            cachedCoinID = symbol.lowercased()
            cachedName = ""
            cachedImageURL = nil
            // PRICE CONSISTENCY FIX: Use bestPrice() for consistent pricing across all views
            cachedPrice = MarketViewModel.shared.bestPrice(forSymbol: symbol)
            cachedRank = nil
            cachedMarketCap = tile.marketCap
            cachedVolume = tile.volume
            // Use tile values directly for consistency with heat map display
            cached1hChange = tile.pctChange1h
            cached24hChange = tile.pctChange24h
            cached7dChange = tile.pctChange7d
        }
    }
    
    private var timeframeLabel: String {
        switch timeframe {
        case .hour1: return "1H"
        case .day1: return "24H"
        case .day7: return "7D"
        }
    }
    
    // Colors matching the Pro palette
    private let cardGreen = Color(red: 0.10, green: 0.90, blue: 0.45)
    private let cardRed = Color(red: 1.00, green: 0.20, blue: 0.20)
    private let cardNeutral = Color(red: 0.45, green: 0.45, blue: 0.50)
    
    // Determine color based on value (neutral for ~0%)
    private func colorForChange(_ value: Double) -> Color {
        if abs(value) < 0.005 { return cardNeutral }
        return value >= 0 ? cardGreen : cardRed
    }
    
    // Helper to detect synthetic "Others" tiles
    private func isOthersID(_ id: String) -> Bool { id.hasPrefix("Others") }

    var body: some View {
        let isOthers = isOthersID(tile.id)
        let ch = (changeProvider?(tile)) ?? HeatMapSharedLib.change(for: tile, tf: timeframe)
        
        // Compact professional card - tap to view details
        Button(action: {
            Haptics.light.impactOccurred()
            if isOthers {
                onViewOthers?()
            } else {
                onViewDetails()
            }
        }) {
            VStack(spacing: 0) {
                // Top section: Logo, Name, Price, Change - more compact
                HStack(spacing: 10) {
                    // Coin logo (smaller)
                    if !isOthers {
                        CoinImageView(symbol: tile.symbol, url: cachedImageURL, size: 44)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                    } else {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.08))
                            Image(systemName: "square.grid.2x2.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .frame(width: 44, height: 44)
                    }
                    
                    // Coin info column - tighter spacing
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(isOthers ? "Others" : tile.symbol)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                            
                            if !isOthers, let rank = cachedRank {
                                Text("#\(rank)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white.opacity(0.5))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.1), in: Capsule())
                            }
                        }
                        
                        if !isOthers {
                            if !cachedName.isEmpty {
                                Text(cachedName)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.5))
                                    .lineLimit(1)
                            }
                        } else {
                            let count = tile.symbol.replacingOccurrences(of: "Others (", with: "").replacingOccurrences(of: ")", with: "")
                            Text("\(count) coins combined")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                        }
                    }
                    
                    Spacer(minLength: 6)
                    
                    // Price and change column - tighter
                    VStack(alignment: .trailing, spacing: 3) {
                        if !isOthers, let price = cachedPrice {
                            Text(MarketFormat.price(price))
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.white)
                        }
                        
                        // Change badge - with neutral color for ~0%
                        Text(HeatMapSharedLib.percentStringAdaptive(ch))
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(colorForChange(ch))
                            )
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)
                
                // Divider
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)
                    .padding(.horizontal, 10)
                
                // Bottom section: Stats row - compact, no sparkline
                HStack(spacing: 12) {
                    // Stats columns - tighter layout
                    if !isOthers {
                        // Market Cap
                        VStack(alignment: .leading, spacing: 1) {
                            Text("MCap")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.white.opacity(0.4))
                            Text(MarketFormat.largeCurrency(cachedMarketCap ?? tile.marketCap))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.white.opacity(0.85))
                        }
                        
                        // Volume
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Vol 24h")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.white.opacity(0.4))
                            Text(MarketFormat.largeCurrency(cachedVolume ?? tile.volume))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.white.opacity(0.85))
                        }
                        
                        Spacer(minLength: 4)
                        
                        // All timeframe changes - labeled pills for clarity
                        HStack(spacing: 4) {
                            changeChip(value: cached1hChange, label: "1H")
                            changeChip(value: cached24hChange, label: "24H")
                            changeChip(value: cached7dChange, label: "7D")
                        }
                    } else {
                        // Others aggregate stats - compact
                        VStack(alignment: .leading, spacing: 1) {
                            Text("MCap")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.white.opacity(0.4))
                            Text(MarketFormat.largeCurrency(tile.marketCap))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.white.opacity(0.85))
                        }
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Vol 24h")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.white.opacity(0.4))
                            Text(MarketFormat.largeCurrency(tile.volume))
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundColor(.white.opacity(0.85))
                        }
                        
                        Spacer()
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
        .onAppear {
            updateCachedCoinData()
        }
        .onChange(of: tile.id) { _, _ in
            updateCachedCoinData()
        }
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.height > 30 {
                        Haptics.light.impactOccurred()
                        onClose()
                    }
                }
        )
    }
    
    // MARK: - Helper Views
    
    @ViewBuilder
    private func changeChip(value: Double?, label: String) -> some View {
        let chipColor: Color = {
            guard let v = value, v.isFinite else { return cardNeutral }
            return colorForChange(v)
        }()
        
        HStack(spacing: 3) {
            // Label (1H, 24H, 7D)
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.white.opacity(0.6))
            
            // Value
            if let v = value, v.isFinite {
                let positive = v >= 0
                Text(String(format: "%@%.1f%%", positive ? "+" : "", v))
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(chipColor)
            } else {
                Text("--")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.3))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(chipColor.opacity(0.15))
                .overlay(
                    Capsule()
                        .stroke(chipColor.opacity(0.25), lineWidth: 0.5)
                )
        )
    }
}
