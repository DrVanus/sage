//
//  PriceViewModel.swift
//  CSAI1
//
//  Updated by ChatGPT on 2025-06-07 to enable live WebSocket updates and fix historical URL builder
//

import Foundation
import Combine
import SwiftUI

// MARK: - ChartTimeframe Definition
enum ChartTimeframe {
    case oneMinute, fiveMinutes, fifteenMinutes, thirtyMinutes
    case oneHour, fourHours, oneDay, oneWeek, oneMonth, threeMonths
    case oneYear, threeYears, allTime
    case live
}

struct BinancePriceResponse: Codable {
    let price: String
}

struct CoinGeckoPriceResponse: Codable {
    let usd: Double
}

struct PriceChartResponse: Codable {
    let prices: [[Double]]
}

@MainActor
class PriceViewModel: ObservableObject {
    // Shared URLSession with custom timeout
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.urlCache = nil
        return URLSession(configuration: config)
    }()
    
    @Published var price: Double = 0
    @Published var symbol: String
    @Published var historicalData: [ChartDataPoint] = []
    @Published var liveData: [ChartDataPoint] = []
    @Published var timeframe: ChartTimeframe
    
    private let service = CryptoAPIService.shared
    // WebSocket-based price publisher service
    private let wsService: PriceService = BinanceWebSocketPriceService()
    private var liveCancellable: AnyCancellable?
    // CoinGecko polling subscription for live prices
    private var livePriceCancellable: AnyCancellable?
    
    private var pollingTask: Task<Void, Never>?
    private let maxBackoff: Double = 60.0
    
    init(symbol: String, timeframe: ChartTimeframe = .live) {
        self.symbol = symbol
        self.timeframe = timeframe
        startPolling()
    }
    
    func updateSymbol(_ newSymbol: String) {
        // Prevent re-subscribing when the symbol hasn’t changed
        guard newSymbol != symbol else {
            print("PriceViewModel: updateSymbol called with same symbol \(newSymbol), skipping")
            return
        }
        symbol = newSymbol
        stopPolling()
        // stopLiveUpdates()
        if timeframe == .live {
            // let id = coingeckoID(for: newSymbol)
            // startLiveUpdates(coinID: id)
            startPolling()
        } else {
            startPolling()
        }
    }
    
    func updateTimeframe(_ newTimeframe: ChartTimeframe) {
        guard newTimeframe != timeframe else { return }
        timeframe = newTimeframe
        stopPolling()
        startPolling()
    }
    
    // MARK: - REST Polling with Backoff
    func startPolling() {
        liveCancellable?.cancel()
        pollingTask?.cancel()
        if timeframe == .live {
            let id = coingeckoID(for: symbol)
            startLiveUpdates(coinID: id)
            return
        }
        pollingTask = Task { [weak self] in
            guard let self = self else { return }
            // Immediate initial fetch
            if let initial = await self.fetchPriceChain(for: self.symbol) {
                await MainActor.run {
                    withAnimation(.linear(duration: 0.2)) {
                        self.price = initial
                    }
                }
            }
            // Start backoff loop
            var delay: Double = 5
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if let newPrice = await self.fetchPriceChain(for: self.symbol) {
                    await MainActor.run {
                        withAnimation(.linear(duration: 0.2)) {
                            self.price = newPrice
                        }
                    }
                    delay = 5
                } else {
                    delay = min(self.maxBackoff, delay * 2)
                }
            }
        }
    }
    
    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        stopLiveUpdates()
    }
    
    // 3-step fallback: CryptoAPIService → Binance → CoinGecko
    private func fetchPriceChain(for symbol: String) async -> Double? {
        if let p = try? await service.fetchSpotPrice(coin: symbol) {
            return p
        }
        if let p = await fetchBinancePrice(for: symbol) {
            return p
        }
        return await fetchCoingeckoPrice(for: symbol)
    }
    
    private func fetchBinancePrice(for symbol: String) async -> Double? {
        let pair = symbol.uppercased() + "USDT"
        guard let url = URL(string: "https://api.binance.com/api/v3/ticker/price?symbol=\(pair)") else { return nil }
        do {
            let (data, _) = try await session.data(from: url)
            let decoded = try JSONDecoder().decode(BinancePriceResponse.self, from: data)
            return Double(decoded.price)
        } catch {
            return nil
        }
    }
    
    /// Map common ticker symbols to CoinGecko IDs
    private func coingeckoID(for symbol: String) -> String {
        switch symbol.uppercased() {
        case "BTC": return "bitcoin"
        case "ETH": return "ethereum"
        case "DOGE": return "dogecoin"
        case "ADA": return "cardano"
        case "SOL": return "solana"
        case "XRP": return "ripple"
        case "DOT": return "polkadot"
        case "MATIC": return "matic-network"
        // add any other symbols you use as needed
        default:
            return symbol.lowercased()
        }
    }
    
    private func fetchCoingeckoPrice(for symbol: String) async -> Double? {
        let id = coingeckoID(for: symbol)
        var comps = URLComponents(string: "https://api.coingecko.com/api/v3/simple/price")
        comps?.queryItems = [
            URLQueryItem(name: "ids", value: id),
            URLQueryItem(name: "vs_currencies", value: "usd")
        ]
        guard let url = comps?.url else { return nil }
        do {
            let (data, _) = try await session.data(from: url)
            let dict = try JSONDecoder().decode([String: CoinGeckoPriceResponse].self, from: data)
            return dict[id]?.usd
        } catch {
            return nil
        }
    }
    
    // MARK: - Live WebSocket Updates
    func startLiveUpdates(coinID: String) {
        // Cancel any existing polling or previous live subscriptions
        pollingTask?.cancel()
        livePriceCancellable?.cancel()

        livePriceCancellable = service
            .liveSpotPricePublisher(for: coinID)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newPrice in
                guard let self = self else { return }
                withAnimation(.linear(duration: 0.2)) {
                    self.price = newPrice
                }
            }
    }
    
    func stopLiveUpdates() {
        livePriceCancellable?.cancel()
        livePriceCancellable = nil
    }
    
    // MARK: - Historical Chart
    func fetchHistoricalData(for coinID: String, timeframe: ChartTimeframe) async {
        guard let url = CryptoAPIService.buildPriceHistoryURL(for: coinID, timeframe: timeframe) else { return }
        do {
            let (data, _) = try await session.data(from: url)
            let decoded = try JSONDecoder().decode(PriceChartResponse.self, from: data)
            let points = decoded.prices.map { arr in
                ChartDataPoint(date: Date(timeIntervalSince1970: arr[0] / 1000), close: arr[1], volume: 0)
            }
            self.historicalData = points
        } catch {
            // handle error
        }
    }
}
