//
//  PortfolioMode.swift
//  CryptoSage
//
//  Created by DM on 5/28/25.
//

import Combine
import Foundation
import SwiftUI

/// Defines which portfolio data source(s) to include
public enum PortfolioMode {
    case manual      // only user-entered transactions
    case synced      // only exchange-synced accounts
    case combined    // merge both manual and synced
}

extension PortfolioRepository {
    /// Shared instance for app-wide use. Prefer using this over creating new instances.
    static let shared = PortfolioRepository()
    
    /// Default initializer that wires up the manual, live, and price services.
    convenience init() {
        self.init(
            manualService: ManualPortfolioDataService(),
            liveService: LivePortfolioDataService(),
            // PERFORMANCE FIX: Use shared singleton to reduce API request storms
            priceService: CoinGeckoPriceService.shared
        )
    }
}

// MARK: - Stock Holdings Integration

extension PortfolioRepository {
    
    /// Publisher for brokerage (stock) holdings
    var brokerageHoldingsPublisher: AnyPublisher<[Holding], Never> {
        BrokeragePortfolioDataService.shared.holdingsPublisher
    }
    
    /// Sync brokerage accounts (stocks/ETFs from Plaid)
    func syncBrokerageAccounts() async {
        await BrokeragePortfolioDataService.shared.syncAllAccounts()
    }
    
    /// Add a manually-entered stock holding
    func addStockHolding(_ holding: Holding) {
        BrokeragePortfolioDataService.shared.addManualHolding(holding)
    }
    
    /// Remove a stock holding
    func removeStockHolding(_ holding: Holding) {
        BrokeragePortfolioDataService.shared.removeHolding(holding)
    }
}

/// Repository that unifies manual entries, live-sync data, brokerage data, and market prices into a single holdings stream.
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
    
    // User preference for showing stocks
    // FIX: @AppStorage doesn't trigger reactivity in non-View classes and captures
    // the value once at init. Use a computed property to read fresh from UserDefaults.
    private var showStocksEnabled: Bool {
        UserDefaults.standard.bool(forKey: "showStocksInPortfolio")
    }

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
                    // STARTUP FIX: Look up the best available price immediately instead of 0.
                    // Previously currentPrice was always 0, causing the portfolio to show $0
                    // for non-stablecoin holdings until the price service responded (~2-3s).
                    // bestPrice(forSymbol:) checks LivePriceManager, allCoins cache, and Firestore.
                    let initialPrice: Double = {
                        if Thread.isMainThread {
                            return MainActor.assumeIsolated { MarketViewModel.shared.bestPrice(forSymbol: symbol) ?? 0 }
                        }
                        var price: Double = 0
                        let group = DispatchGroup()
                        group.enter()
                        DispatchQueue.main.async {
                            price = MainActor.assumeIsolated { MarketViewModel.shared.bestPrice(forSymbol: symbol) ?? 0 }
                            group.leave()
                        }
                        if group.wait(timeout: .now() + 0.5) == .timedOut {
                            #if DEBUG
                            print("[PortfolioRepository] Warning: main thread access timed out for \(symbol)")
                            #endif
                            return 0
                        }
                        return price
                    }()
                    return Holding(
                        id: UUID(),
                        coinName: symbol,
                        coinSymbol: symbol,
                        quantity: qty,
                        currentPrice: initialPrice,
                        costBasis: 0,
                        imageUrl: "",
                        isFavorite: false,
                        dailyChange: 0,
                        purchaseDate: Date()
                    )
                }
            }
            .eraseToAnyPublisher()

        // Combine crypto holdings (manual + exchange-synced)
        let cryptoHoldings = Publishers.CombineLatest(
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
        
        // Combine crypto holdings with brokerage (stock) holdings
        let allHoldings = Publishers.CombineLatest(
            cryptoHoldings,
            BrokeragePortfolioDataService.shared.holdingsPublisher
        )
        .map { [weak self] (pair: ([Holding], [Holding])) -> [Holding] in
            let crypto = pair.0
            let brokerageHoldings = pair.1
            
            // Commodities (gold, silver, etc.) should always appear in the portfolio
            let commodities = brokerageHoldings.filter { $0.assetType == .commodity }
            let stocksAndETFs = brokerageHoldings.filter { $0.assetType == .stock || $0.assetType == .etf }
            
            // Only include stocks/ETFs if user has enabled the feature
            if self?.showStocksEnabled == true {
                return crypto + stocksAndETFs + commodities
            } else {
                return crypto + commodities
            }
        }
        .eraseToAnyPublisher()

        // Reactive pipeline: whenever holdings change, fetch prices and update currentPrice
        // Note: Stock prices are managed separately by LiveStockPriceManager
        allHoldings
            .receive(on: DispatchQueue.main)
            .flatMap { [weak self] holdingsList -> AnyPublisher<[Holding], Never> in
                guard let self = self else {
                    return Just(holdingsList).eraseToAnyPublisher()
                }
                
                // Separate crypto and stock/commodity holdings
                let cryptoHoldings = holdingsList.filter { $0.assetType == .crypto }
                let stockHoldings = holdingsList.filter { $0.assetType == .stock || $0.assetType == .etf || $0.assetType == .commodity }
                
                // Only fetch prices for crypto symbols (stocks handled by LiveStockPriceManager)
                let cryptoSymbols = cryptoHoldings.map { $0.coinSymbol }
                
                // If no crypto symbols, just return all holdings as-is
                if cryptoSymbols.isEmpty {
                    return Just(holdingsList).eraseToAnyPublisher()
                }
                
                return self.priceService
                    .pricePublisher(for: cryptoSymbols, interval: 60)
                    .map { pricesMap in
                        // Update crypto holdings with live prices
                        var updatedHoldings = cryptoHoldings.map { h -> Holding in
                            var updated = h
                            if let price = pricesMap[h.coinSymbol], price > 0 {
                                updated.currentPrice = price
                            } else if updated.currentPrice <= 0 {
                                // STARTUP FIX: If price service returned nothing and holding has no price,
                                // try bestPrice as a last resort. This prevents showing $0 in the portfolio.
                                if Thread.isMainThread {
                                    let fallback = MainActor.assumeIsolated { MarketViewModel.shared.bestPrice(forSymbol: h.coinSymbol) }
                                    if let price = fallback, price > 0 {
                                        updated.currentPrice = price
                                    }
                                }
                            }
                            return updated
                        }
                        // Add stock holdings back (already have prices from LiveStockPriceManager)
                        updatedHoldings.append(contentsOf: stockHoldings)
                        return updatedHoldings
                    }
                    .replaceError(with: holdingsList)
                    .eraseToAnyPublisher()
            }
            .assign(to: &$holdings)
    }
}

