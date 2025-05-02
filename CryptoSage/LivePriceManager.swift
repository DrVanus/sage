import Foundation
import Combine

final class LivePriceManager {
    static let shared = LivePriceManager()

    // Map from ticker symbol to CoinGecko ID
    var geckoIDMap: [String: String] = [
        "btc": "bitcoin", "eth": "ethereum", "bnb": "binancecoin",
        "usdt": "tether",
        "busd": "binance-usd", "usdc": "usd-coin", "sol": "solana",
        "ada": "cardano", "xrp": "ripple", "doge": "dogecoin",
        "dot": "polkadot", "avax": "avalanche-2", "matic": "matic-network",
        "link": "chainlink", "xlm": "stellar", "bch": "bitcoin-cash",
        "trx": "tron", "uni": "uniswap", "etc": "ethereum-classic",
        "wbtc": "wrapped-bitcoin", "steth": "staked-ether",
        "wsteth": "wrapped-steth", "sui": "sui", "hype": "hyperliquid",
        "leo": "leo-token", "fil": "filecoin",
        "hbar": "hedera",
        "shib": "shiba-inu",
        "rlc": "iexec-rlc"
    ]

    // Timer for polling
    private var timerCancellable: AnyCancellable?

    // Subject to broadcast MarketCoin arrays
    private let coinSubject = PassthroughSubject<[MarketCoin], Never>()

    /// Publisher for live-updated MarketCoin arrays
    var coinsPublisher: AnyPublisher<[MarketCoin], Never> {
        coinSubject.eraseToAnyPublisher()
    }

    /// Alias for coinsPublisher for shorthand subscriptions
    var publisher: AnyPublisher<[MarketCoin], Never> {
        coinsPublisher
    }

    /// Begin polling MarketCoin data every 60 seconds by default
    func startPolling(interval: TimeInterval = 60) {
        stopPolling()
        Task { await self.pollMarketCoins() }
        timerCancellable = Timer
            .publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { await self?.pollMarketCoins() }
            }
    }

    // Stop the polling timer
    func stopPolling() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    /// Polls market data and emits via coinSubject
    private func pollMarketCoins() async {
        do {
            let coins = try await CryptoAPIService.shared.fetchMarketCoins()
            coinSubject.send(coins)
        } catch {
            print("LivePriceManager poll error:", error)
        }
    }
}
