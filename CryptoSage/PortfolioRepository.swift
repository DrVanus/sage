//
//  PortfolioMode.swift
//  CryptoSage
//
//  Created by DM on 5/28/25.
//

import Combine
import Foundation

/// Defines which portfolio data source(s) to include
public enum PortfolioMode {
    case manual      // only user-entered transactions
    case synced      // only exchange-synced accounts
    case combined    // merge both manual and synced
}

extension PortfolioRepository {
    /// Default initializer that wires up the manual, live, and price services.
    convenience init() {
        self.init(
            manualService: ManualPortfolioDataService(),
            liveService: LivePortfolioDataService(),
            priceService: CoinGeckoPriceService()
        )
    }
}

/// Repository that unifies manual entries, live-sync data, and market prices into a single holdings stream.
final class PortfolioRepository {
    // MARK: - Public publishers

    /// Emits the current array of Holdings (after applying mode filter and live pricing)
    var holdingsPublisher: AnyPublisher<[Holding], Never> {
        $holdings.eraseToAnyPublisher()
    }

    /// Emits the current list of transactions based on the selected mode
    var transactionsPublisher: AnyPublisher<[Transaction], Never> {
        Publishers.CombineLatest(
            manualService.transactionsPublisher,
            liveService.transactionsPublisher
        )
        .map { manual, live in manual + live }
        .eraseToAnyPublisher()
    }

    /// Forwards to the priceService to publish live price updates
    func pricePublisher(
        for symbols: [String],
        interval: TimeInterval
    ) -> AnyPublisher<[String: Double], Never> {
        priceService.pricePublisher(for: symbols, interval: interval)
    }

    /// Current portfolio assets with live prices
    @Published private var holdings: [Holding] = []

    // MARK: - Private state

    private let manualService: PortfolioDataService
    private let liveService: PortfolioDataService
    private let priceService: PriceService
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization
    
    /// Initialize the repository with required services and a mode manager.
    /// - Parameters:
    ///   - manualService: source for user-entered transactions
    ///   - liveService: source for exchange-synced holdings
    ///   - priceService: source for live price quotes
    init(
        manualService: PortfolioDataService,
        liveService: PortfolioDataService,
        priceService: PriceService
    ) {
        self.manualService = manualService
        self.liveService = liveService
        self.priceService = priceService

        bindDataSources()
    }

    // MARK: - Data binding
    
    private func bindDataSources() {
        // Convert manual transactions into aggregated holdings
        let manualHoldingsPublisher = manualService.transactionsPublisher
            .map { transactions -> [Holding] in
                var aggregates: [String: Double] = [:]
                for tx in transactions {
                    aggregates[tx.coinSymbol, default: 0] += tx.quantity
                }
                return aggregates.map { (symbol: String, qty: Double) -> Holding in
                    return Holding(
                        id: UUID(),
                        coinName: symbol,
                        coinSymbol: symbol,
                        quantity: qty,
                        currentPrice: 0,
                        costBasis: 0,
                        imageUrl: "",
                        isFavorite: false,
                        dailyChange: 0,
                        purchaseDate: Date()
                    )
                }
            }
            .eraseToAnyPublisher()

        let baseHoldings = Publishers.CombineLatest(
            manualHoldingsPublisher,
            liveService.holdingsPublisher
        )
        .map({ (pair: ([Holding], [Holding])) -> [Holding] in
            let manual = pair.0
            let live = pair.1
            var combined = manual
            for h in live {
                if !combined.contains(where: { $0.coinSymbol == h.coinSymbol }) {
                    combined.append(h)
                }
            }
            return combined
        })
        .eraseToAnyPublisher()

        // Reactive pipeline: whenever baseHoldings change, fetch prices and update currentPrice
        baseHoldings
            .receive(on: DispatchQueue.main)
            .flatMap { holdingsList -> AnyPublisher<[Holding], Never> in
                let symbols = holdingsList.map { $0.coinSymbol }
                return self.priceService
                    .pricePublisher(for: symbols, interval: 60)
                    .map { pricesMap in
                        holdingsList.map { h in
                            var updated = h
                            if let price = pricesMap[h.coinSymbol] {
                                updated.currentPrice = price
                            }
                            return updated
                        }
                    }
                    .replaceError(with: holdingsList)
                    .eraseToAnyPublisher()
            }
            .assign(to: &$holdings)
    }
}
