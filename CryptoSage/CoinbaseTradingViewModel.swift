//
//  CoinbaseTradingViewModel.swift
//  CryptoSage
//
//  Trading ViewModel for Coinbase Advanced Trade integration
//  Connects UI with CoinbaseAdvancedTradeService
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class CoinbaseTradingViewModel: ObservableObject {
    static let shared = CoinbaseTradingViewModel()

    // MARK: - Published State
    @Published var accounts: [CoinbaseAccount] = []
    @Published var openOrders: [CoinbaseOrder] = []
    @Published var orderHistory: [CoinbaseOrder] = []
    @Published var isConnected: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // Paper trading mode
    @Published var isPaperTrading: Bool = true

    // MARK: - Services
    private let coinbaseService = CoinbaseAdvancedTradeService.shared
    private let paperTradingManager = PaperTradingManager.shared

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Check if credentials exist
        checkConnection()
    }

    // MARK: - Connection

    func checkConnection() {
        isConnected = TradingCredentialsManager.shared.hasCredentials(for: .coinbase)
    }

    func connect() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Test connection
            let connected = try await coinbaseService.testConnection()
            isConnected = connected

            if connected {
                // Load initial data
                await loadAccounts()
                await loadOpenOrders()
            }
        } catch {
            errorMessage = error.localizedDescription
            isConnected = false
        }
    }

    func disconnect() async {
        isConnected = false
        accounts = []
        openOrders = []
    }

    // MARK: - Account Management

    func loadAccounts() async {
        do {
            accounts = try await coinbaseService.fetchAccounts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func getBalance(for currency: String) -> Double {
        accounts.first(where: { $0.currency.uppercased() == currency.uppercased() })?.totalBalance ?? 0
    }

    // MARK: - Order Management

    func placeMarketOrder(
        productId: String,
        side: TradeSide,
        size: Double,
        isSizeInQuote: Bool = false
    ) async throws {
        // Paper trading mode
        if isPaperTrading {
            let symbol = productId.replacingOccurrences(of: "-USD", with: "")
            let price = MarketViewModel.shared.bestPrice(forSymbol: symbol) ?? 0

            try paperTradingManager.executePaperTrade(
                symbol: productId,
                side: side,
                quantity: size,
                price: price,
                orderType: "MARKET"
            )
            return
        }

        // Live trading
        let response = try await coinbaseService.placeMarketOrder(
            productId: productId,
            side: side.rawValue.uppercased(),
            size: size,
            isSizeInQuote: isSizeInQuote
        )

        if !response.success {
            throw CoinbaseError.orderRejected(reason: response.errorResponse?.message ?? "Unknown error")
        }

        // Refresh orders and balances
        await loadOpenOrders()
        await loadAccounts()
    }

    func placeLimitOrder(
        productId: String,
        side: TradeSide,
        size: Double,
        price: Double,
        postOnly: Bool = false
    ) async throws {
        // Paper trading mode
        if isPaperTrading {
            _ = paperTradingManager.executePaperTrade(
                symbol: productId,
                side: side,
                quantity: size,
                price: price,
                orderType: "LIMIT"
            )
            return
        }

        // Live trading
        let response = try await coinbaseService.placeLimitOrder(
            productId: productId,
            side: side.rawValue.uppercased(),
            size: size,
            price: price,
            postOnly: postOnly
        )

        if !response.success {
            throw CoinbaseError.orderRejected(reason: response.errorResponse?.message ?? "Unknown error")
        }

        await loadOpenOrders()
    }

    func cancelOrder(orderId: String) async throws {
        // Paper trading mode
        if isPaperTrading {
            _ = paperTradingManager.cancelPendingOrder(orderId: orderId)
            return
        }

        // Live trading
        _ = try await coinbaseService.cancelOrder(orderId: orderId)
        await loadOpenOrders()
    }

    func loadOpenOrders(productId: String? = nil) async {
        do {
            openOrders = try await coinbaseService.getOpenOrders(productId: productId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helper Methods

    func formatBalance(_ balance: Double, currency: String) -> String {
        if currency == "USD" || currency == "USDC" || currency == "USDT" {
            return String(format: "$%.2f", balance)
        } else if balance < 0.001 {
            return String(format: "%.8f %@", balance, currency)
        } else if balance < 1 {
            return String(format: "%.6f %@", balance, currency)
        } else {
            return String(format: "%.4f %@", balance, currency)
        }
    }
}
