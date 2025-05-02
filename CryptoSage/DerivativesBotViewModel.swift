//
//  DerivativesBotViewModel.swift
//  CryptoSage
//
//  Created by DM on 5/29/25.
//

import SwiftUI
import Combine

// MARK: - DerivativesBotViewModel
class DerivativesBotViewModel: ObservableObject {
    // MARK: - UI State
    enum BotTab: String, CaseIterable, Identifiable, Hashable {
        case chat = "AI Chat"
        case strategy = "Strategy"
        case risk = "Risk & Accounts"
        var id: String { rawValue }
        var title: String { rawValue }
    }

    @Published var selectedTab: BotTab = .chat

    // Grid strategy inputs
    @Published var lowerPrice: String = ""
    @Published var upperPrice: String = ""
    @Published var gridLevels: String = ""
    @Published var orderVolume: String = ""

    // Chat history
    @Published var chatMessages: [ChatMessage] = []

    // Maximum leverage for UI
    let maxLeverage: Int = 125
    // MARK: Published properties for UI binding
    @Published var availableDerivativesExchanges: [Exchange] = []
    @Published var marketsForSelectedExchange: [Market] = []
    @Published var selectedExchange: Exchange? = nil { didSet { fetchMarkets() } }
    @Published var selectedMarket: Market? = nil
    @Published var leverage: Int = 5
    @Published var isIsolated: Bool = false
    @Published var isRunning: Bool = false
    
    // MARK: Dependencies
    private var cancellables = Set<AnyCancellable>()
    private let exchangeService: DerivativesExchangeServiceProtocol
    private let botService: DerivativesBotServiceProtocol
    
    // MARK: Init
    init(
        exchangeService: DerivativesExchangeServiceProtocol = DerivativesExchangeService(),
        botService: DerivativesBotServiceProtocol = DerivativesBotService()
    ) {
        self.exchangeService = exchangeService
        self.botService = botService
        fetchExchanges()
    }
    
    // MARK: Fetch available exchanges (e.g. Binance, KuCoin)
    func fetchExchanges() {
        exchangeService.getSupportedExchanges()
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] exs in
                self?.availableDerivativesExchanges = exs
                if self?.selectedExchange == nil {
                    // Default to Coinbase if available
                    self?.selectedExchange = exs.first(where: { $0.id == "coinbase" }) ?? exs.first
                }
            })
            .store(in: &cancellables)
    }
    
    // MARK: Fetch markets for selected exchange
    func fetchMarkets() {
        guard let ex = selectedExchange else { return }
        exchangeService.getMarkets(for: ex)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { _ in }, receiveValue: { [weak self] mks in
                self?.marketsForSelectedExchange = mks
                if self?.selectedMarket == nil {
                    self?.selectedMarket = mks.first
                }
            })
            .store(in: &cancellables)
    }
    
    // MARK: Generate strategy via AI
    func generateDerivativesConfig() {
        // TODO: use lowerPrice, upperPrice, gridLevels, orderVolume to call AI service
    }

    /// Load previous chat messages from backend or local cache
    func loadChatHistory() {
        // TODO: fetch and assign to chatMessages
    }

    /// Send a new message via AI chat
    func sendChatMessage(_ text: String) {
        // Append to local history
        let outgoing = ChatMessage(id: UUID(), sender: "User", text: text)
        chatMessages.append(outgoing)
        // TODO: call AI chat service, append response to chatMessages
    }
    
    // MARK: Start/Stop bot
    func toggleDerivativesBot() {
        if isRunning {
            stopBot()
        } else {
            startBot()
        }
    }

    /// Starts the derivatives bot using a provided configuration.
    func startBot(with config: DerivativesBotConfig) {
        // Update view model state from the passed-in config
        self.selectedExchange = config.exchange
        self.selectedMarket = config.market
        self.leverage = config.leverage
        self.isIsolated = config.isIsolated
        // Call the existing startBot() logic
        startBot()
    }

    private func startBot() {
        guard let ex = selectedExchange, let mk = selectedMarket else { return }
        let config = DerivativesBotConfig(exchange: ex,
                                          market: mk,
                                          leverage: leverage,
                                          isIsolated: isIsolated)
        botService.startBot(with: config)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: { completion in
                if case .failure(let err) = completion {
                    print("Failed to start derivatives bot: \(err)")
                }
            }, receiveValue: { [weak self] in
                self?.isRunning = true
            })
            .store(in: &cancellables)
    }
    
    private func stopBot() {
        botService.stopBot()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                self?.isRunning = false
            } receiveValue: { }
            .store(in: &cancellables)
    }
}

// MARK: - Supporting Protocols & Models

protocol DerivativesExchangeServiceProtocol {
    func getSupportedExchanges() -> AnyPublisher<[Exchange], Error>
    func getMarkets(for exchange: Exchange) -> AnyPublisher<[Market], Error>
}

class DerivativesExchangeService: DerivativesExchangeServiceProtocol {
    func getSupportedExchanges() -> AnyPublisher<[Exchange], Error> {
        // TODO: call backend endpoint `/exchanges/derivatives`
        Just([Exchange(name: "Coinbase", id: "coinbase"),
              Exchange(name: "Binance", id: "binance"),
              Exchange(name: "KuCoin", id: "kucoin")])
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
    
    func getMarkets(for exchange: Exchange) -> AnyPublisher<[Market], Error> {
        // TODO: call backend `/exchanges/\(exchange.id)/markets`
        Just([Market(symbol: "BTCUSDT", title: "BTC/USDT Perp")])
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
}

protocol DerivativesBotServiceProtocol {
    func startBot(with config: DerivativesBotConfig) -> AnyPublisher<Void, Error>
    func stopBot() -> AnyPublisher<Void, Error>
}

class DerivativesBotService: DerivativesBotServiceProtocol {
    func startBot(with config: DerivativesBotConfig) -> AnyPublisher<Void, Error> {
        // TODO: POST to `/bot/derivatives/start`
        return Just(()).setFailureType(to: Error.self).eraseToAnyPublisher()
    }
    
    func stopBot() -> AnyPublisher<Void, Error> {
        // TODO: POST to `/bot/derivatives/stop`
        return Just(()).setFailureType(to: Error.self).eraseToAnyPublisher()
    }
}

// Data models
struct Exchange: Identifiable, Hashable {
    let name: String
    let id: String
}

struct Market: Identifiable, Hashable {
    let symbol: String
    let title: String
    var id: String { symbol }
}

struct DerivativesBotConfig {
    let exchange: Exchange
    let market: Market
    let leverage: Int
    let isIsolated: Bool
}
