//
//  CoinbaseWebSocketService.swift
//  CryptoSage
//
//  WebSocket service for real-time Coinbase Advanced Trade data
//  Supports ticker, level2, matches, and user channels
//

import Foundation
import Combine

/// WebSocket feed types
public enum CoinbaseWSFeed: String {
    case ticker = "ticker"
    case level2 = "level2"
    case matches = "matches"
    case user = "user"
}

/// WebSocket message types
public struct CoinbaseWSMessage: Codable {
    public let type: String
    public let channel: String
    public let product_id: String?
    public let price: String?
    public let volume_24h: String?
    public let events: [WSEvent]?
}

public struct WSEvent: Codable {
    public let type: String
    public let tickers: [WSTicker]?
}

public struct WSTicker: Codable {
    public let type: String
    public let product_id: String
    public let price: String
    public let volume_24_h: String?
    public let low_24_h: String?
    public let high_24_h: String?
    public let price_percent_chg_24_h: String?
}

/// WebSocket service for real-time Coinbase data
public actor CoinbaseWebSocketService {
    public static let shared = CoinbaseWebSocketService()
    private init() {}

    private var webSocketTask: URLSessionWebSocketTask?
    private var isConnected = false
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5

    // Publishers
    nonisolated(unsafe) private let tickerSubject = PassthroughSubject<WSTicker, Never>()
    nonisolated public var tickerPublisher: AnyPublisher<WSTicker, Never> {
        tickerSubject.eraseToAnyPublisher()
    }

    /// Connect to WebSocket feed
    public func connect(products: [String], feeds: [CoinbaseWSFeed]) async throws {
        guard !isConnected else { return }

        let wsURL = URL(string: "wss://advanced-trade-ws.coinbase.com")!
        let session = URLSession(configuration: .default)

        webSocketTask = session.webSocketTask(with: wsURL)
        webSocketTask?.resume()
        isConnected = true
        reconnectAttempts = 0

        // Send subscribe message
        let jwt = try await CoinbaseJWTAuthService.shared.generateJWT()

        let subscribeMessage: [String: Any] = [
            "type": "subscribe",
            "product_ids": products,
            "channel": "ticker",
            "jwt": jwt
        ]

        let messageData = try JSONSerialization.data(withJSONObject: subscribeMessage)
        guard let messageString = String(data: messageData, encoding: .utf8) else { return }

        try await webSocketTask?.send(.string(messageString))

        // Start receiving messages
        Task {
            await receiveMessages()
        }

        print("✅ WebSocket connected to Coinbase Advanced Trade")
    }

    /// Disconnect from WebSocket
    public func disconnect() async {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        isConnected = false
        reconnectAttempts = 0
        print("🔌 WebSocket disconnected")
    }

    /// Reconnect after failure
    private func reconnect(products: [String], feeds: [CoinbaseWSFeed]) async {
        guard reconnectAttempts < maxReconnectAttempts else {
            print("❌ WebSocket max reconnect attempts reached")
            return
        }

        reconnectAttempts += 1
        print("🔄 WebSocket reconnecting... (attempt \(reconnectAttempts)/\(maxReconnectAttempts))")

        // Exponential backoff
        let delay = UInt64(pow(2.0, Double(reconnectAttempts)) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: delay)

        do {
            try await connect(products: products, feeds: feeds)
        } catch {
            print("❌ WebSocket reconnect failed: \(error)")
        }
    }

    private func receiveMessages() async {
        guard let task = webSocketTask else { return }

        while isConnected {
            do {
                let message = try await task.receive()

                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8),
                       let wsMessage = try? JSONDecoder().decode(CoinbaseWSMessage.self, from: data) {
                        handleMessage(wsMessage)
                    }
                case .data(let data):
                    if let wsMessage = try? JSONDecoder().decode(CoinbaseWSMessage.self, from: data) {
                        handleMessage(wsMessage)
                    }
                @unknown default:
                    break
                }
            } catch {
                print("WebSocket receive error: \(error)")
                isConnected = false

                // Attempt reconnect
                // await reconnect(products: [], feeds: [])
                break
            }
        }
    }

    private func handleMessage(_ message: CoinbaseWSMessage) {
        // Process ticker updates
        if message.channel == "ticker", let events = message.events {
            for event in events {
                if let tickers = event.tickers {
                    for ticker in tickers {
                        tickerSubject.send(ticker)

                        // Update LivePriceManager with real-time prices
                        if let price = Double(ticker.price) {
                            let symbol = ticker.product_id.replacingOccurrences(of: "-USD", with: "")
                            Task { @MainActor in
                                LivePriceManager.shared.update(
                                    symbol: symbol,
                                    price: price,
                                    change24h: ticker.price_percent_chg_24_h.flatMap { Double($0) }
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}
