//
//  PortfolioDataService.swift
//  CryptoSage
//
//  Created by DM on 5/28/25.
//


import Combine

/// Abstract interface for feeding PortfolioViewModel its holdings & transactions.
protocol PortfolioDataService {
  /// Emits the current list of holdings (built from transactions or mock config).
  var holdingsPublisher: AnyPublisher<[Holding], Never> { get }

  /// Emits the current list of manual transactions (so a UI can drive edits).
  var transactionsPublisher: AnyPublisher<[Transaction], Never> { get }

  /// Call to add/remove/update a transaction; service will recalc holdings and emit new values.
  func addTransaction(_ tx: Transaction)
  func updateTransaction(_ old: Transaction, with new: Transaction)
  func deleteTransaction(_ tx: Transaction)
}