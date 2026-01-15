import SwiftUI
import Combine

// MARK: - Models

struct ExchangeQuote: Identifiable, Hashable {
    let id = UUID()
    let exchange: String
    let symbol: String
    let price: Double
    let volume24h: Double?
}

struct ArbitrageOpportunity: Identifiable, Hashable {
    let id = UUID()
    let symbol: String
    let buyExchange: String
    let buyPrice: Double
    let sellExchange: String
    let sellPrice: Double
    let spreadPercent: Double
    let volumeSellExchange24h: Double?
    var formattedSpread: String {
        String(format: "%.2f%%", spreadPercent)
    }
    var formattedBuyPrice: String {
        String(format: "%.4f", buyPrice)
    }
    var formattedSellPrice: String {
        String(format: "%.4f", sellPrice)
    }
}

// MARK: - ViewModel

@MainActor
class ArbitrageViewModel: ObservableObject {
    @Published var opportunities: [ArbitrageOpportunity] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    
    private var refreshTask: Task<Void, Never>? = nil
    
    private let defaultSymbols = [
        "BTCUSDT", "ETHUSDT", "BNBUSDT", "XRPUSDT", "ADAUSDT",
        "SOLUSDT", "DOGEUSDT", "DOTUSDT", "MATICUSDT", "LTCUSDT"
    ]
    
    private let exchanges = [
        BinanceAPI(),
        KucoinAPI(),
        BybitAPI()
    ]
    
    func refreshOpportunities(using marketVM: MarketViewModel) {
        refreshTask?.cancel()
        refreshTask = Task {
            await fetchOpportunities(using: marketVM)
        }
    }
    
    func startAutoRefresh(using marketVM: MarketViewModel, intervalSeconds: UInt64 = 30) {
        refreshTask?.cancel()
        refreshTask = Task {
            while !Task.isCancelled {
                await fetchOpportunities(using: marketVM)
                try? await Task.sleep(nanoseconds: intervalSeconds * 1_000_000_000)
            }
        }
    }
    
    func stopAutoRefresh() {
        refreshTask?.cancel()
    }
    
    private func fetchOpportunities(using marketVM: MarketViewModel) async {
        isLoading = true
        errorMessage = nil
        
        // Prepare symbols to scan
        let symbolsToScan: [String]
        if !marketVM.marketCoins.isEmpty {
            symbolsToScan = marketVM.marketCoins
                .map { $0.symbol.uppercased() }
                .filter { $0.hasSuffix("USDT") }
        } else {
            symbolsToScan = defaultSymbols
        }
        
        do {
            // Fetch quotes concurrently per exchange
            let exchangeQuotesList = try await withThrowingTaskGroup(of: [ExchangeQuote].self) { group in
                for exchange in exchanges {
                    group.addTask {
                        try await exchange.fetchQuotes(for: symbolsToScan)
                    }
                }
                var allQuotes: [[ExchangeQuote]] = []
                for try await quotes in group {
                    allQuotes.append(quotes)
                }
                return allQuotes
            }
            
            // Flatten quotes and group by symbol
            var symbolToQuotes: [String: [ExchangeQuote]] = [:]
            for quotes in exchangeQuotesList {
                for quote in quotes {
                    symbolToQuotes[quote.symbol, default: []].append(quote)
                }
            }
            
            var foundOps: [ArbitrageOpportunity] = []
            for (symbol, quotes) in symbolToQuotes {
                guard quotes.count >= 2 else { continue }
                
                // Find best buy (lowest price) and best sell (highest price) quote
                let sortedByPriceAsc = quotes.sorted { $0.price < $1.price }
                let bestBuy = sortedByPriceAsc.first!
                let bestSell = sortedByPriceAsc.last!
                
                // Calculate spread percent
                // Use USDT ~ USD, so direct price comparison is valid
                guard bestSell.price > bestBuy.price else { continue }
                let spread = (bestSell.price - bestBuy.price) / bestBuy.price * 100
                
                // Consider volume on sell side > 0 to avoid fake opps
                if let vol = bestSell.volume24h, vol > 0, spread >= 0.15 {
                    let opp = ArbitrageOpportunity(
                        symbol: symbol,
                        buyExchange: bestBuy.exchange,
                        buyPrice: bestBuy.price,
                        sellExchange: bestSell.exchange,
                        sellPrice: bestSell.price,
                        spreadPercent: spread,
                        volumeSellExchange24h: bestSell.volume24h
                    )
                    foundOps.append(opp)
                }
            }
            
            // Sort opportunities by spread descending
            foundOps.sort { $0.spreadPercent > $1.spreadPercent }
            
            opportunities = foundOps
        } catch {
            errorMessage = "Failed to fetch arbitrage data: \(error.localizedDescription)"
            opportunities = []
        }
        isLoading = false
    }
}


// MARK: - Exchange APIs

private protocol ExchangeAPI {
    var name: String { get }
    func fetchQuotes(for symbols: [String]) async throws -> [ExchangeQuote]
}

private struct BinanceAPI: ExchangeAPI {
    let name = "Binance"
    
    func fetchQuotes(for symbols: [String]) async throws -> [ExchangeQuote] {
        // Binance API: https://api.binance.com/api/v3/ticker/24hr?symbols=["BTCUSDT","ETHUSDT"]
        guard !symbols.isEmpty else { return [] }
        let encodedSymbols = symbols.map { "\"\($0)\"" }.joined(separator: ",")
        let urlString = "https://api.binance.com/api/v3/ticker/24hr?symbols=[\(encodedSymbols)]"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        // Response: Array of objects like:
        /*
         [
           {
             "symbol": "BNBUSDT",
             "priceChange": "15.00000000",
             "priceChangePercent": "1.074",
             "weightedAvgPrice": "1400.00000000",
             "prevClosePrice": "1398.00000000",
             "lastPrice": "1413.00000000",
             "lastQty": "0.10000000",
             "bidPrice": "1412.95000000",
             "bidQty": "5.00000000",
             "askPrice": "1413.00000000",
             "askQty": "3.00000000",
             "openPrice": "1398.00000000",
             "highPrice": "1420.00000000",
             "lowPrice": "1390.00000000",
             "volume": "10234.56000000",
             "quoteVolume": "14320000.00000000",
             "openTime": 1620000000000,
             "closeTime": 1620086399999,
             "firstId": 123456,
             "lastId": 123789,
             "count": 334
           },
           ...
         ]
         */
        
        struct BinanceTicker: Decodable {
            let symbol: String
            let lastPrice: String
            let volume: String
            
            var priceDouble: Double? {
                Double(lastPrice)
            }
            var volumeDouble: Double? {
                Double(volume)
            }
        }
        
        let decoded = try JSONDecoder().decode([BinanceTicker].self, from: data)
        return decoded.compactMap {
            guard let price = $0.priceDouble else { return nil }
            return ExchangeQuote(
                exchange: name,
                symbol: $0.symbol.uppercased(),
                price: price,
                volume24h: $0.volumeDouble
            )
        }
    }
}

private struct KucoinAPI: ExchangeAPI {
    let name = "Kucoin"
    
    func fetchQuotes(for symbols: [String]) async throws -> [ExchangeQuote] {
        // Kucoin API batch endpoint supports symbols in comma separated list
        // Example: https://api.kucoin.com/api/v1/market/allTickers
        // But it returns all tickers so we filter client-side
        let urlString = "https://api.kucoin.com/api/v1/market/allTickers"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        /*
         Response JSON:
         {
           "code": "200000",
           "data": {
             "time": 1620080000000,
             "ticker": [
               {
                 "symbol": "BTC-USDT",
                 "last": "57000.12",
                 "buy": "56999.11",
                 "sell": "57001.13",
                 "changeRate": "0.023",
                 "changePrice": "1300",
                 "high": "58000.00",
                 "low": "56000.00",
                 "vol": "1234.56",
                 "volValue": "70000000"
               },
               ...
             ]
           }
         }
         */
        
        struct KucoinResponse: Decodable {
            struct Data: Decodable {
                struct Ticker: Decodable {
                    let symbol: String
                    let last: String
                    let volValue: String
                    
                    var priceDouble: Double? { Double(last) }
                    var volumeDouble: Double? { Double(volValue) }
                }
                let ticker: [Ticker]
            }
            let code: String
            let data: Data?
        }
        
        let decoded = try JSONDecoder().decode(KucoinResponse.self, from: data)
        guard decoded.code == "200000", let tickers = decoded.data?.ticker else {
            throw NSError(domain: "KucoinAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        // Kucoin symbols use "-" as separator, convert to uppercase and remove "-"
        let filteredTickers = tickers.filter {
            symbols.contains($0.symbol.replacingOccurrences(of: "-", with: "").uppercased())
        }
        
        return filteredTickers.compactMap {
            guard let price = $0.priceDouble else { return nil }
            let symbol = $0.symbol.replacingOccurrences(of: "-", with: "").uppercased()
            return ExchangeQuote(
                exchange: name,
                symbol: symbol,
                price: price,
                volume24h: $0.volumeDouble
            )
        }
    }
}

private struct BybitAPI: ExchangeAPI {
    let name = "Bybit"
    
    func fetchQuotes(for symbols: [String]) async throws -> [ExchangeQuote] {
        // Bybit REST API: https://api.bybit.com/v2/public/tickers
        // No batch symbols filter, return all and filter client side
        let urlString = "https://api.bybit.com/v2/public/tickers"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        
        /*
         {
           "ret_code": 0,
           "ret_msg": "OK",
           "ext_code": "",
           "ext_info": "",
           "result": [
             {
               "symbol": "BTCUSDT",
               "bid_price": "56800.5",
               "ask_price": "56801.0",
               "last_price": "56800.75",
               "last_tick_direction": "PlusTick",
               "prev_price_24h": "56000.0",
               "price_24h_pcnt": "0.0143",
               "high_price_24h": "57000.0",
               "low_price_24h": "55000.0",
               "volume_24h": "1200.5",
               "turnover_24h": "68000000.0"
             },
             ...
           ],
           "time_now": "1620080000.123"
         }
         */
        
        struct BybitResponse: Decodable {
            struct ResultItem: Decodable {
                let symbol: String
                let last_price: String
                let volume_24h: String
                
                var priceDouble: Double? { Double(last_price) }
                var volumeDouble: Double? { Double(volume_24h) }
            }
            let ret_code: Int
            let ret_msg: String
            let result: [ResultItem]?
        }
        
        let decoded = try JSONDecoder().decode(BybitResponse.self, from: data)
        guard decoded.ret_code == 0, let results = decoded.result else {
            throw NSError(domain: "BybitAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        let filtered = results.filter { symbols.contains($0.symbol.uppercased()) }
        
        return filtered.compactMap {
            guard let price = $0.priceDouble else { return nil }
            return ExchangeQuote(
                exchange: name,
                symbol: $0.symbol.uppercased(),
                price: price,
                volume24h: $0.volumeDouble
            )
        }
    }
}

// MARK: - View

struct ArbitrageSectionView: View {
    @EnvironmentObject private var marketVM: MarketViewModel
    @StateObject private var vm = ArbitrageViewModel()
    @State private var autoRefreshEnabled = true
    
    var body: some View {
        Section(header: headerView) {
            if vm.isLoading && vm.opportunities.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if let error = vm.errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.footnote)
                    .padding(.vertical, 6)
            } else if vm.opportunities.isEmpty {
                Text("No arbitrage opportunities found.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(vm.opportunities.prefix(10)) { opp in
                    ArbitrageRow(opportunity: opp)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            notificationOpenTrade(symbol: opp.symbol)
                        }
                }
            }
        }
        .onAppear {
            vm.refreshOpportunities(using: marketVM)
            if autoRefreshEnabled {
                vm.startAutoRefresh(using: marketVM)
            }
        }
        .onDisappear {
            vm.stopAutoRefresh()
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    autoRefreshEnabled.toggle()
                    if autoRefreshEnabled {
                        vm.startAutoRefresh(using: marketVM)
                    } else {
                        vm.stopAutoRefresh()
                    }
                } label: {
                    Image(systemName: autoRefreshEnabled ? "arrow.clockwise.circle.fill" : "arrow.clockwise.circle")
                        .imageScale(.large)
                        .accessibilityLabel(autoRefreshEnabled ? "Disable Auto Refresh" : "Enable Auto Refresh")
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    vm.refreshOpportunities(using: marketVM)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .imageScale(.large)
                        .accessibilityLabel("Refresh Arbitrage Opportunities")
                }
            }
        }
    }
    
    private var headerView: some View {
        HStack {
            Text("Arbitrage Opportunities")
                .font(.headline)
            Spacer()
            if vm.isLoading {
                ProgressView()
                    .scaleEffect(0.6, anchor: .center)
            }
        }
    }
    
    private func notificationOpenTrade(symbol: String) {
        NotificationCenter.default.post(name: .openTradeView, object: nil, userInfo: ["symbol": symbol])
    }
}

private struct ArbitrageRow: View {
    let opportunity: ArbitrageOpportunity
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(opportunity.symbol)
                    .font(.subheadline)
                    .bold()
                HStack(spacing: 6) {
                    Text("Buy:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(opportunity.buyExchange) @ \(opportunity.formattedBuyPrice)")
                        .font(.caption2.monospaced())
                        .foregroundColor(.green)
                }
                HStack(spacing: 6) {
                    Text("Sell:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(opportunity.sellExchange) @ \(opportunity.formattedSellPrice)")
                        .font(.caption2.monospaced())
                        .foregroundColor(.red)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(opportunity.formattedSpread)
                    .font(.subheadline.monospacedDigit())
                    .bold()
                    .foregroundColor(spreadColor)
                if let vol = opportunity.volumeSellExchange24h {
                    Text("Vol: \(formatVolume(vol))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private var spreadColor: Color {
        switch opportunity.spreadPercent {
        case 0.15..<0.5: return .orange
        case 0.5..<2: return .yellow
        case 2...: return .green
        default: return .primary
        }
    }
    
    private func formatVolume(_ v: Double) -> String {
        if v >= 1_000_000_000 {
            return String(format: "%.2fB", v / 1_000_000_000)
        } else if v >= 1_000_000 {
            return String(format: "%.2fM", v / 1_000_000)
        } else if v >= 1_000 {
            return String(format: "%.1fK", v / 1_000)
        } else {
            return String(format: "%.0f", v)
        }
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let openTradeView = Notification.Name("OpenTradeViewNotification")
}

// MARK: - Preview

#if DEBUG
import Foundation

// Dummy MarketViewModel and MarketCoin implementations for preview only

final class MarketCoin: ObservableObject {
    let symbol: String
    init(symbol: String) {
        self.symbol = symbol
    }
}

final class MarketViewModel: ObservableObject {
    @Published var marketCoins: [MarketCoin] = [
        MarketCoin(symbol: "BTCUSDT"),
        MarketCoin(symbol: "ETHUSDT"),
        MarketCoin(symbol: "BNBUSDT")
    ]
}

struct ArbitrageSectionView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            List {
                ArbitrageSectionView()
                    .environmentObject(MarketViewModel())
            }
            .navigationTitle("Market")
        }
    }
}
#endif
