//
//  ManualPortfolioDataService.swift
//  CryptoSage
//
//  Created by DM on 5/28/25.
//


import Combine
import Foundation

final class ManualPortfolioDataService: PortfolioDataService {
  /// Subjects to emit current holdings and transactions
  private let holdingsSubject = CurrentValueSubject<[Holding], Never>([])
  private let transactionsSubject = CurrentValueSubject<[Transaction], Never>([])

  var holdingsPublisher: AnyPublisher<[Holding], Never> {
    holdingsSubject.eraseToAnyPublisher()
  }
  var transactionsPublisher: AnyPublisher<[Transaction], Never> {
    transactionsSubject.eraseToAnyPublisher()
  }

  /// Initialize with optional starting holdings and transactions
  init(initialHoldings: [Holding] = [], initialTransactions: [Transaction] = []) {
    holdingsSubject.send(initialHoldings)
    transactionsSubject.send(initialTransactions)
    // If transactions provided, build holdings from them
    if !initialTransactions.isEmpty {
      rebuildHoldingsFromTransactions()
    }
  }

  func addTransaction(_ tx: Transaction) {
    transactionsSubject.send(transactionsSubject.value + [tx])
    rebuildHoldingsFromTransactions()
  }
  func updateTransaction(_ old: Transaction, with new: Transaction) {
    let updated = transactionsSubject.value.map { $0.id == old.id ? new : $0 }
    transactionsSubject.send(updated)
    rebuildHoldingsFromTransactions()
  }
  func deleteTransaction(_ tx: Transaction) {
    let remaining = transactionsSubject.value.filter { $0.id != tx.id }
    transactionsSubject.send(remaining)
    rebuildHoldingsFromTransactions()
  }

  private func rebuildHoldingsFromTransactions() {
    // Group by coinSymbol (normalized to uppercase to prevent "btc"/"BTC" split)
    let txns = transactionsSubject.value
    let grouped = Dictionary(grouping: txns, by: { $0.coinSymbol.uppercased() })
    let newHoldings: [Holding] = grouped.compactMap { symbol, txs in
        // FIX: Properly handle buy vs sell transactions.
        // Previously all tx.quantity was added, ignoring isBuy flag.
        // This caused sells to INCREASE the holding quantity instead of decreasing it.
        var totalBuyQuantity: Double = 0
        var totalBuyCost: Double = 0
        var netQuantity: Double = 0
        
        for tx in txs {
            if tx.isBuy {
                totalBuyQuantity += tx.quantity
                totalBuyCost += tx.quantity * tx.pricePerUnit
                netQuantity += tx.quantity
            } else {
                netQuantity -= tx.quantity
            }
        }
        
        // Skip fully sold positions
        guard netQuantity > 0 else { return nil }
        
        let averageCostBasis = totalBuyQuantity > 0 ? totalBuyCost / totalBuyQuantity : 0
        
        // FIX: Use human-readable coin name instead of raw symbol
        let displayName = coinName(for: symbol)
        
        // Build holding with cost-basis price initially.
        // Live prices are applied asynchronously below via updateHoldingsWithLivePrices().
        return Holding(
            coinName: displayName,
            coinSymbol: symbol,
            quantity: netQuantity,
            currentPrice: averageCostBasis,
            costBasis: averageCostBasis,
            imageUrl: nil,
            isFavorite: false,
            dailyChange: 0,
            purchaseDate: txs.first?.date ?? Date()
        )
    }
    holdingsSubject.send(newHoldings)
    
    // Asynchronously update with live market prices from MarketViewModel (MainActor-isolated).
    // This avoids calling @MainActor methods from a nonisolated synchronous context.
    Task { @MainActor [weak self] in
        self?.updateHoldingsWithLivePrices()
    }
  }
    
  /// Refresh holdings with live prices from MarketViewModel.
  /// Must run on MainActor since MarketViewModel.shared is MainActor-isolated.
  @MainActor
  private func updateHoldingsWithLivePrices() {
    let current = holdingsSubject.value
    guard !current.isEmpty else { return }
    
    var didChange = false
    let updated: [Holding] = current.map { holding in
        let symbol = holding.coinSymbol.uppercased()
        
        if let price = MarketViewModel.shared.bestPrice(forSymbol: symbol), price > 0 {
            if price != holding.currentPrice {
                didChange = true
                var h = holding
                h.currentPrice = price
                return h
            }
        } else if let coin = MarketViewModel.shared.allCoins.first(where: {
            $0.symbol.uppercased() == symbol
        }), let price = coin.priceUsd, price > 0 {
            if price != holding.currentPrice {
                didChange = true
                var h = holding
                h.currentPrice = price
                return h
            }
        }
        return holding
    }
    
    if didChange {
        holdingsSubject.send(updated)
    }
  }
    
  /// Map common symbols to readable names
  private func coinName(for symbol: String) -> String {
    let names: [String: String] = [
        "BTC": "Bitcoin", "ETH": "Ethereum", "SOL": "Solana",
        "ADA": "Cardano", "XRP": "XRP", "DOGE": "Dogecoin",
        "DOT": "Polkadot", "LINK": "Chainlink", "AVAX": "Avalanche",
        "MATIC": "Polygon", "BNB": "BNB", "SHIB": "Shiba Inu",
        "LTC": "Litecoin", "UNI": "Uniswap", "ATOM": "Cosmos",
    ]
    return names[symbol.uppercased()] ?? symbol
  }
}
