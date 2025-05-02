//
//  LivePortfolioDataService.swift
//  CryptoSage
//
//  Created by DM on 5/28/25.
//  Live implementation stub for fetching user’s synced portfolio data.

import Combine
import Foundation

final class LivePortfolioDataService: PortfolioDataService {
  // Here you’d wire up 3Commas API + a local transaction store
  // to produce two publishers, and implement add/update/delete
  // by writing to your local DB or sending to your backend.

  private let holdingsSubject = CurrentValueSubject<[Holding], Never>([])
  private let transactionsSubject = CurrentValueSubject<[Transaction], Never>([])

  var holdingsPublisher: AnyPublisher<[Holding], Never> {
      holdingsSubject.eraseToAnyPublisher()
  }

  var transactionsPublisher: AnyPublisher<[Transaction], Never> {
      transactionsSubject.eraseToAnyPublisher()
  }

  func addTransaction(_ tx: Transaction) {
      // TODO: integrate with live backend
  }

  func updateTransaction(_ old: Transaction, with new: Transaction) {
      // TODO: integrate with live backend
  }

  func deleteTransaction(_ tx: Transaction) {
      // TODO: integrate with live backend
  }
}
