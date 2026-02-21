//
//  PortfolioLegendView.swift
//  CSAI1
//
//  Created by DM on 3/26/25.
//


import SwiftUI

struct PortfolioLegendView: View {
    let holdings: [Holding]
    let totalValue: Double
    /// Optional color map from the pie chart so legend dots match slice colors exactly.
    /// When nil, falls back to PortfolioViewModel's deterministic color palette.
    var colorMap: [String: Color]? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(holdings) { holding in
                let val = holding.currentPrice * holding.quantity
                let pct = totalValue > 0 ? (val / totalValue * 100) : 0
                HStack(spacing: 6) {
                    Circle()
                        .fill(sliceColor(for: holding.coinSymbol))
                        .frame(width: 8, height: 8)
                    
                    Text("\(holding.coinSymbol) \(String(format: "%.1f", pct))%")
                        .font(.caption2)
                        .foregroundColor(.white)
                }
            }
        }
    }
    
    /// Returns the slice color for the given symbol.
    /// Prefers colors from the pie chart's `colorMap` so legend dots always match
    /// the actual donut slices. Falls back to the same deterministic hex palette
    /// used by `PortfolioViewModel.color(for:)`.
    private func sliceColor(for symbol: String) -> Color {
        if let mapped = colorMap?[symbol] { return mapped }

        // Deterministic palette matching PortfolioViewModel.color(for:)
        let palette: [UInt32] = [
            0x2891FF, 0x1ABC9C, 0xF39C12, 0x9B59B6,
            0xE74C3C, 0x2ECC71, 0xE84393, 0x8E44AD,
            0x2980B9, 0x00C2FF, 0xF1C40F, 0x16A085,
            0x34495E, 0xFF4D4F, 0x27AE60, 0xD35400
        ]
        // Stable hash that won't vary between launches (hashValue is randomised)
        let stable = symbol.utf8.reduce(0) { ($0 &* 31) &+ Int($1) }
        let hex = palette[abs(stable) % palette.count]
        return Color(
            red:   Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8)  & 0xFF) / 255.0,
            blue:  Double( hex        & 0xFF) / 255.0
        )
    }
}

struct PortfolioLegendView_Previews: PreviewProvider {
    static var previews: some View {
        PortfolioLegendView(holdings: [
            Holding(id: UUID(), coinName: "Bitcoin", coinSymbol: "BTC", quantity: 1.0, currentPrice: 30000, costBasis: 25000, imageUrl: nil, isFavorite: false, dailyChange: 2.0, purchaseDate: Date()),
            Holding(id: UUID(), coinName: "Ethereum", coinSymbol: "ETH", quantity: 10, currentPrice: 2000, costBasis: 1800, imageUrl: nil, isFavorite: false, dailyChange: -1.5, purchaseDate: Date())
        ], totalValue: (30000 * 1.0) + (2000 * 10))
        .preferredColorScheme(.dark)
        .previewLayout(.sizeThatFits)
    }
}
