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
    // Group by coinSymbol and sum quantities and cost basis
    let txns = transactionsSubject.value
    let grouped = Dictionary(grouping: txns, by: { $0.coinSymbol })
    let newHoldings: [Holding] = grouped.map { symbol, txs in
        let totalQuantity = txs.reduce(into: 0.0) { acc, tx in
            acc += tx.quantity
        }
        let totalCost = txs.reduce(into: 0.0) { acc, tx in
            acc += tx.quantity * tx.pricePerUnit
        }
        let averageCostBasis = totalQuantity > 0 ? totalCost / totalQuantity : 0
        return Holding(
            coinName: symbol,
            coinSymbol: symbol,
            quantity: totalQuantity,
            currentPrice: averageCostBasis,
            costBasis: averageCostBasis,
            imageUrl: nil,
            isFavorite: false,
            dailyChange: 0,
            purchaseDate: txs.first!.date
        )
    }
    holdingsSubject.send(newHoldings)
  }
}
