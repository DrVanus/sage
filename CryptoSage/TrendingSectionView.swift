import SwiftUI
import Combine

struct TrendingSectionView: View {
    let coins: [MarketCoin]
    let maxItemsPerList: Int
    let onSelect: ((MarketCoin) -> Void)?
    
    @State private var selectedTab: Int = 0
    
    private static let stableSet: Set<String> = [
        "USDT","USDC","BUSD","DAI","TUSD","USDP","FDUSD","PYUSD","GUSD","FRAX","LUSD"
    ]
    
    init(coins: [MarketCoin],
         maxItemsPerList: Int = 5,
         onSelect: ((MarketCoin) -> Void)? = nil) {
        self.coins = coins
        self.maxItemsPerList = maxItemsPerList
        self.onSelect = onSelect
    }
    
    private func isStable(_ symbol: String) -> Bool {
        Self.stableSet.contains(symbol.uppercased())
    }
    
    private func dayChange(_ coin: MarketCoin) -> Double? {
        if let val = coin.priceChangePercentage24hInCurrency {
            return val
        }
        if let val = coin.changePercent24Hr {
            return val
        }
        return nil
    }
    
    private func price(_ coin: MarketCoin) -> Double? {
        coin.priceUsd
    }
    
    private func bestVolumeUSD(for coin: MarketCoin) -> Double? {
        if let manager = try? LivePriceManager.shared {
            // On MainActor per requirement
            var vol: Double?
            Task {
                await MainActor.run {
                    vol = manager.bestVolumeUSD(for: coin)
                }
            }
            if let v = vol {
                return v
            }
        }
        if let vol = coin.totalVolume {
            return vol
        }
        return nil
    }
    
    private var filteredCoins: [MarketCoin] {
        coins.filter {
            guard let symbol = $0.symbol, !isStable(symbol) else { return false }
            guard let priceUsd = price($0), priceUsd > 0 else { return false }
            guard let change24h = dayChange($0) else { return false }
            if let volume = bestVolumeUSD(for: $0) {
                return volume >= 1_000_000
            }
            return true
        }
    }
    
    private var trending: [MarketCoin] {
        filteredCoins
            .compactMap { coin -> (MarketCoin, Double)? in
                guard let change = dayChange(coin) else { return nil }
                let volume = bestVolumeUSD(for: coin) ?? 10_000
                let score = abs(change) * log10(max(volume, 10_000))
                return (coin, score)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(maxItemsPerList)
            .map { $0.0 }
    }
    
    private var gainers: [MarketCoin] {
        filteredCoins
            .filter { (dayChange($0) ?? 0) > 0 }
            .sorted {
                (dayChange($0) ?? 0) > (dayChange($1) ?? 0)
            }
            .prefix(maxItemsPerList)
            .map { $0 }
    }
    
    private var losers: [MarketCoin] {
        filteredCoins
            .filter { (dayChange($0) ?? 0) < 0 }
            .sorted {
                (dayChange($0) ?? 0) < (dayChange($1) ?? 0)
            }
            .prefix(maxItemsPerList)
            .map { $0 }
    }
    
    private var currentList: [MarketCoin] {
        switch selectedTab {
        case 0: return trending
        case 1: return gainers
        case 2: return losers
        default: return []
        }
    }
    
    var body: some View {
        VStack(spacing: 6) {
            // Header with title and segmented picker
            HStack(spacing: 12) {
                Text("Market Movers")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Picker("", selection: $selectedTab) {
                    Text("Trending").tag(0)
                    Text("Gainers").tag(1)
                    Text("Losers").tag(2)
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 260)
            }
            .padding(.horizontal, 8)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(currentList, id: \.id) { coin in
                        CoinCardView(coin: coin,
                                     onSelect: onSelect)
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 64)
        }
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.15), radius: 5, x: 0, y: 2)
        )
    }
    
    private struct CoinCardView: View {
        let coin: MarketCoin
        let onSelect: ((MarketCoin) -> Void)?
        
        private var symbol: String {
            coin.symbol ?? "?"
        }
        
        private var priceString: String {
            if let price = coin.priceUsd {
                return price.formattedCurrency()
            }
            return "-"
        }
        
        private var dayChangePercent: Double? {
            if let val = coin.priceChangePercentage24hInCurrency {
                return val
            }
            if let val = coin.changePercent24Hr {
                return val
            }
            return nil
        }
        
        private var dayChangeColor: Color {
            guard let change = dayChangePercent else { return .white }
            return change >= 0 ? .green : .red
        }
        
        var body: some View {
            Button(action: {
                onSelect?(coin)
            }) {
                HStack(spacing: 8) {
                    CoinImageView(coin: coin)
                        .frame(width: 28, height: 28)
                        .clipShape(Circle())
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(symbol)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        if let price = coin.priceUsd {
                            AnimatedPriceText(price: price)
                                .font(.footnote.monospacedDigit())
                                .foregroundColor(.white.opacity(0.8))
                        } else {
                            Text("-")
                                .font(.footnote.monospacedDigit())
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                    
                    Spacer(minLength: 8)
                    
                    if let change = dayChangePercent {
                        Text(change, format: .percent.precision(.fractionLength(2)))
                            .font(.footnote.monospacedDigit())
                            .foregroundColor(dayChangeColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(dayChangeColor.opacity(0.15))
                            .clipShape(Capsule())
                    } else {
                        Text("-")
                            .font(.footnote.monospacedDigit())
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(height: 64)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.12), radius: 5, x: 0, y: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

#if DEBUG
private struct MarketCoinMock: Identifiable {
    let id = UUID().uuidString
    let symbol: String
    let priceUsd: Double
    let priceChangePercentage24hInCurrency: Double?
    let changePercent24Hr: Double?
    let totalVolume: Double?
    let imageURL: URL?
}

extension MarketCoin {
    init(mock: MarketCoinMock) {
        self.init(
            id: mock.id,
            symbol: mock.symbol,
            name: mock.symbol + " Coin",
            imageURL: mock.imageURL,
            priceUsd: mock.priceUsd,
            priceChangePercentage24hInCurrency: mock.priceChangePercentage24hInCurrency,
            changePercent24Hr: mock.changePercent24Hr,
            totalVolume: mock.totalVolume,
            // other properties defaulted to nil or 0
            circulatingSupply: nil,
            maxSupply: nil,
            marketCapUsd: nil,
            rank: nil,
            sparkline: nil,
            lastUpdated: nil,
            priceBtc: nil,
            volume: nil,
            volumeUsd24Hr: nil,
            symbolId: nil,
            supply: nil,
            symbolIdPlus: nil
        )
    }
}

struct TrendingSectionView_Previews: PreviewProvider {
    static var previews: some View {
        let mocks = [
            MarketCoinMock(
                symbol: "BTC",
                priceUsd: 30500,
                priceChangePercentage24hInCurrency: 3.5,
                changePercent24Hr: nil,
                totalVolume: 2_000_000_000,
                imageURL: nil
            ),
            MarketCoinMock(
                symbol: "ETH",
                priceUsd: 1900,
                priceChangePercentage24hInCurrency: 5.2,
                changePercent24Hr: nil,
                totalVolume: 1_500_000_000,
                imageURL: nil
            ),
            MarketCoinMock(
                symbol: "DOGE",
                priceUsd: 0.06,
                priceChangePercentage24hInCurrency: -2.0,
                changePercent24Hr: nil,
                totalVolume: 500_000_000,
                imageURL: nil
            ),
            MarketCoinMock(
                symbol: "SOL",
                priceUsd: 20.5,
                priceChangePercentage24hInCurrency: -1.1,
                changePercent24Hr: nil,
                totalVolume: 1_200_000_000,
                imageURL: nil
            ),
            MarketCoinMock(
                symbol: "ADA",
                priceUsd: 0.35,
                priceChangePercentage24hInCurrency: 0.6,
                changePercent24Hr: nil,
                totalVolume: 900_000_000,
                imageURL: nil
            ),
            MarketCoinMock(
                symbol: "USDT",
                priceUsd: 1,
                priceChangePercentage24hInCurrency: 0.0,
                changePercent24Hr: nil,
                totalVolume: 10_000_000_000,
                imageURL: nil
            )
        ]
        
        let coins = mocks.map(MarketCoin.init)
        
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            TrendingSectionView(coins: coins)
                .padding()
                .preferredColorScheme(.dark)
        }
        .frame(height: 140)
    }
}
#endif
