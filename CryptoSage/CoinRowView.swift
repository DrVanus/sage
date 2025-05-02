
import SwiftUI

extension Double {
    /// Shortens large numbers: 1.2K, 3.4M, etc.
    func formattedWithAbbreviations() -> String {
        let absValue = abs(self)
        switch absValue {
        case 1_000_000_000_000...:
            return String(format: "%.1fT", self / 1_000_000_000_000)
        case 1_000_000_000...:
            return String(format: "%.1fB", self / 1_000_000_000)
        case 1_000_000...:
            return String(format: "%.1fM", self / 1_000_000)
        case 1_000...:
            return String(format: "%.1fK", self / 1_000)
        default:
            return String(format: "%.0f", self)
        }
    }
}

/// Simple sparkline for 7-day price movement.
struct CoinSparklineView: View {
    let prices: [Double]
    var body: some View {
        GeometryReader { geo in
            let maxPrice = prices.max() ?? 0
            let minPrice = prices.min() ?? 0
            Path { path in
                for (index, price) in prices.enumerated() {
                    let xPos = geo.size.width * CGFloat(index) / CGFloat(prices.count - 1)
                    let normalized = (price - minPrice) / (maxPrice - minPrice == 0 ? 1 : (maxPrice - minPrice))
                    let yPos = geo.size.height * (1 - CGFloat(normalized))
                    if index == 0 {
                        path.move(to: CGPoint(x: xPos, y: yPos))
                    } else {
                        path.addLine(to: CGPoint(x: xPos, y: yPos))
                    }
                }
            }
            .stroke(Color.white.opacity(0.7), lineWidth: 1)
        }
    }
}

/// A reusable row view for displaying a single coin in a list.
struct CoinRowView: View {
    let coin: MarketCoin
    @ObservedObject private var favorites = FavoritesManager.shared
    @EnvironmentObject private var viewModel: MarketViewModel

    // Constants for column widths
    private let imageSize: CGFloat = 32
    private let starSize: CGFloat = 20
    private let sparklineWidth: CGFloat = 50
    private let priceWidth: CGFloat = 70
    private let changeWidth: CGFloat = 50
    private let volumeWidth: CGFloat = 50
    private let starColumnWidth: CGFloat = 40
    private let rowPadding: CGFloat = 8

    /// Formats the price dynamically: no decimals for large prices, two decimals for mid-range, and up to six decimals for sub-dollar prices.
    private var formattedPrice: String {
        let price = coin.priceUsd ?? 0
        if price >= 1000 {
            return String(format: "$%.0f", price)
        } else if price >= 1 {
            return String(format: "$%.2f", price)
        } else {
            return String(format: "$%.6f", price)
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            // 1) Coin icon + symbol/name
            HStack(spacing: 8) {
                CoinImageView(symbol: coin.symbol, url: coin.imageUrl, size: imageSize)
                    .frame(width: imageSize, height: imageSize)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(coin.symbol.uppercased())
                        .font(.subheadline)
                        .bold()
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(coin.name)
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(width: 100, alignment: .leading)
            .padding(.leading, rowPadding)

            // 2) 7-day sparkline
            if coin.sparklineIn7d.count > 1 {
                CoinSparklineView(prices: coin.sparklineIn7d)
                    .frame(width: sparklineWidth, height: 20)
                    .padding(.horizontal, rowPadding / 2)
            } else {
                Color.clear
                    .frame(width: sparklineWidth, height: 20)
                    .padding(.horizontal, rowPadding / 2)
            }

            // 3) Price column
            Text(formattedPrice)
                .font(.subheadline)
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: priceWidth, alignment: .trailing)
                .padding(.horizontal, rowPadding / 2)

            // 4) 24h change column
            let change24h = coin.changePercent24Hr ?? 0
            Text(String(format: "%@%.2f%%", change24h >= 0 ? "+" : "", change24h))
                .font(.caption)
                .foregroundColor(change24h >= 0 ? .green : .red)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: changeWidth, alignment: .trailing)
                .padding(.horizontal, rowPadding / 2)
                .animation(.easeInOut, value: change24h)

            // 5) Volume column
            let volumeValue = coin.volumeUsd24Hr ?? 0
            Text(volumeValue.formattedWithAbbreviations())
                .font(.caption2)
                .foregroundColor(.white.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: volumeWidth, alignment: .trailing)
                .padding(.horizontal, rowPadding / 2)

            // 6) Favorite star column
            Button {
                favorites.toggle(coinID: coin.id)
                viewModel.favoriteIDs = FavoritesManager.shared.getAllIDs()
                viewModel.applyAllFiltersAndSort()
                Task { await viewModel.loadWatchlistData() }
            } label: {
                Image(systemName: favorites.isFavorite(coinID: coin.id) ? "star.fill" : "star")
                    .resizable()
                    .scaledToFit()
                    .frame(width: starSize, height: starSize)
                    .foregroundColor(favorites.isFavorite(coinID: coin.id) ? .yellow : .white.opacity(0.6))
            }
            .frame(width: starColumnWidth, alignment: .center)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, rowPadding)
        .background(Color.clear)
    }
}

// MARK: - Previews and Sample Data
#if DEBUG
struct CoinRowView_Previews: PreviewProvider {
    static var previews: some View {
        // Sample JSON matching MarketCoin properties
        let json = """
        {
            "id": "bitcoin",
            "symbol": "btc",
            "name": "Bitcoin",
            "image": "https://assets.coingecko.com/coins/images/1/large/bitcoin.png",
            "current_price": 106344,
            "total_volume": 27200000000,
            "price_change_percentage_24h": 1.92
        }
        """
        // Decode JSON into a MarketCoin instance
        let data = Data(json.utf8)
        let decoder = JSONDecoder()
        let sampleCoin = try! decoder.decode(MarketCoin.self, from: data)

        CoinRowView(coin: sampleCoin)
            .environmentObject(MarketViewModel.shared)
            .previewLayout(.sizeThatFits)
            .background(Color.black)
    }
}
#endif
