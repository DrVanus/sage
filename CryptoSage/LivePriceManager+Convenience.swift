import Foundation

extension LivePriceManager {
    func bestChange24hPercent(for coin: MarketCoin?) -> Double? {
        guard let coin = coin else { return nil }
        return bestChange24hPercent(for: coin)
    }
    func bestChange1hPercent(for coin: MarketCoin?) -> Double? {
        guard let coin = coin else { return nil }
        return bestChange1hPercent(for: coin)
    }
    func bestChange7dPercent(for coin: MarketCoin?) -> Double? {
        guard let coin = coin else { return nil }
        return bestChange7dPercent(for: coin)
    }
}
