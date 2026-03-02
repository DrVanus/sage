//
//  LivePortfolioDataService.swift
//  CryptoSage
//
//  Created by DM on 5/28/25.
//  Live implementation for fetching user's synced portfolio data from 3Commas.

import Combine
import Foundation

final class LivePortfolioDataService: PortfolioDataService {
    
    // MARK: - Publishers
    
    let holdingsSubject = CurrentValueSubject<[Holding], Never>([])
    private let transactionsSubject = CurrentValueSubject<[Transaction], Never>([])

    var holdingsPublisher: AnyPublisher<[Holding], Never> {
        holdingsSubject.eraseToAnyPublisher()
    }

    var transactionsPublisher: AnyPublisher<[Transaction], Never> {
        transactionsSubject.eraseToAnyPublisher()
    }

    // MARK: - State

    var cancellables = Set<AnyCancellable>()
    private let accountsManager = ConnectedAccountsManager.shared
    private var isRefreshing = false
    private var lastRefreshTime: Date?
    private let refreshCooldown: TimeInterval = 30 // seconds
    
    // Local transaction store (now using secure encrypted storage)
    private let secureDataManager = SecureUserDataManager.shared
    private var localTransactions: [Transaction] = []
    
    // MARK: - Mock Data
    
    private static let mockHoldings: [Holding] = [
        Holding(
            coinName: "Bitcoin",
            coinSymbol: "BTC",
            quantity: 0.5,
            currentPrice: 42000,
            costBasis: 35000,
            imageUrl: nil,
            isFavorite: true,
            dailyChange: 2.5,
            purchaseDate: Date().addingTimeInterval(-86400 * 30)
        ),
        Holding(
            coinName: "Ethereum",
            coinSymbol: "ETH",
            quantity: 3.0,
            currentPrice: 2200,
            costBasis: 1800,
            imageUrl: nil,
            isFavorite: true,
            dailyChange: -1.2,
            purchaseDate: Date().addingTimeInterval(-86400 * 60)
        ),
        Holding(
            coinName: "Solana",
            coinSymbol: "SOL",
            quantity: 50.0,
            currentPrice: 95,
            costBasis: 80,
            imageUrl: nil,
            isFavorite: false,
            dailyChange: 5.8,
            purchaseDate: Date().addingTimeInterval(-86400 * 14)
        ),
        Holding(
            coinName: "Dogecoin",
            coinSymbol: "DOGE",
            quantity: 10000,
            currentPrice: 0.08,
            costBasis: 0.05,
            imageUrl: nil,
            isFavorite: false,
            dailyChange: 3.2,
            purchaseDate: Date().addingTimeInterval(-86400 * 90)
        ),
        Holding(
            coinName: "Tether",
            coinSymbol: "USDT",
            quantity: 5000,
            currentPrice: 1.0,
            costBasis: 1.0,
            imageUrl: nil,
            isFavorite: false,
            dailyChange: 0.0,
            purchaseDate: Date().addingTimeInterval(-86400 * 7)
        )
    ]
    
    // MARK: - Initialization
    
    init() {
        loadLocalTransactions()
        
        // Observe account changes
        accountsManager.objectWillChange
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                Task {
                    await self?.refreshHoldings()
                }
            }
            .store(in: &cancellables)
        
        // Initial fetch
        Task {
            await refreshHoldings()
        }
    }
    
    // MARK: - Refresh Holdings
    
    /// Refresh holdings from all connected providers (3Commas, Direct API, OAuth, Blockchain)
    func refreshHoldings() async {
        // Prevent concurrent refreshes
        guard !isRefreshing else { return }

        // Check cooldown
        if let lastRefresh = lastRefreshTime,
           Date().timeIntervalSince(lastRefresh) < refreshCooldown {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        // Check if we have connected accounts
        guard !accountsManager.accounts.isEmpty else {
            await MainActor.run {
                holdingsSubject.send([])
            }
            return
        }

        // Fetch from all connected accounts, routing through the correct provider
        var allHoldings: [Holding] = []

        for account in accountsManager.accounts {
            do {
                // Fetch raw balances based on provider type
                let rawBalances: [(symbol: String, balance: Double)]

                switch account.provider {
                case "3commas":
                    // 3Commas uses integer accountId
                    guard let tcAccountId = account.accountId else { continue }
                    let tcBalances = try await ThreeCommasAPI.shared.loadAccountBalances(accountId: tcAccountId)
                    rawBalances = tcBalances.map { ($0.currency, $0.balance) }

                case "direct", "oauth", "blockchain":
                    // Route through the real ConnectionProvider implementation
                    let connectionType: ConnectionType = {
                        switch account.provider {
                        case "oauth": return .oauth
                        case "blockchain": return .walletAddress
                        default: return .apiKey
                        }
                    }()
                    guard let provider = accountsManager.provider(for: connectionType) else { continue }
                    let pBalances = try await provider.fetchBalances(accountId: account.id)
                    rawBalances = pBalances.map { ($0.symbol, $0.balance) }

                default:
                    continue
                }

                // Convert balances to holdings (unified for all providers)
                for entry in rawBalances where entry.balance > 0 {
                    // Skip very small balances
                    guard entry.balance > 0.00001 else { continue }

                    // Fetch current price for the currency
                    let price = await fetchPrice(for: entry.symbol)

                    // Determine asset type: commodity for precious metals, crypto otherwise
                    let isPreciousMetal = PreciousMetalsHelper.isPreciousMetal(entry.symbol)
                    let assetType: AssetType = isPreciousMetal ? .commodity : .crypto

                    // PRICE CONSISTENCY: Get 24h change from unified pipeline (LivePriceManager)
                    let dailyPct: Double = await MainActor.run {
                        let coins = LivePriceManager.shared.currentCoinsList
                        if let coin = coins.first(where: { $0.symbol.uppercased() == entry.symbol.uppercased() }),
                           let change = LivePriceManager.shared.bestChange24hPercent(for: coin),
                           change.isFinite {
                            return change
                        }
                        return 0
                    }

                    // Create holding with appropriate asset type
                    var holding = Holding(
                        coinName: coinName(for: entry.symbol),
                        coinSymbol: entry.symbol,
                        quantity: entry.balance,
                        currentPrice: price,
                        costBasis: price, // Cost basis unavailable from balance APIs
                        imageUrl: nil,
                        isFavorite: false,
                        dailyChange: dailyPct,
                        purchaseDate: Date()
                    )

                    // Set the asset type for precious metals
                    holding.assetType = assetType

                    // Check for duplicate and merge
                    if let existingIndex = allHoldings.firstIndex(where: { $0.coinSymbol == entry.symbol }) {
                        allHoldings[existingIndex].quantity += entry.balance
                    } else {
                        allHoldings.append(holding)
                    }
                }

                // Update last sync time
                accountsManager.updateLastSync(for: account)

            } catch {
                #if DEBUG
                print("⚠️ [LivePortfolio] Failed to fetch holdings for \(account.name): \(error)")
                #endif
                // Continue with other accounts — don't fail entire refresh for one provider
            }
        }

        // Sort by value (descending)
        allHoldings.sort { $0.currentValue > $1.currentValue }

        // Capture immutable copy to avoid "captured var in concurrently-executing code"
        let finalHoldings = allHoldings
        await MainActor.run {
            holdingsSubject.send(finalHoldings)
            lastRefreshTime = Date()
        }
    }
    
    // MARK: - Price Fetching
    
    /// Price cache to reduce API calls for repeated symbols
    private var priceCache: [String: (price: Double, timestamp: Date)] = [:]
    private let priceCacheTTL: TimeInterval = 30 // 30 second cache
    
    private func fetchPrice(for symbol: String) async -> Double {
        let upperSymbol = symbol.uppercased()
        
        // ROBUSTNESS: Check cache first to reduce API load
        if let cached = priceCache[upperSymbol],
           Date().timeIntervalSince(cached.timestamp) < priceCacheTTL {
            return cached.price
        }
        
        var price: Double = 0
        
        // Check if this is a precious metal - use Coinbase directly (Binance/CoinGecko won't have these)
        let isPreciousMetal = PreciousMetalsHelper.isPreciousMetal(upperSymbol)
        
        if isPreciousMetal {
            // For precious metals, use Coinbase directly since that's where they're traded
            if let coinbasePrice = await CoinbaseService.shared.fetchSpotPrice(coin: upperSymbol), coinbasePrice > 0 {
                price = coinbasePrice
                #if DEBUG
                print("💰 [LivePortfolioDataService] Fetched precious metal price for \(upperSymbol): $\(coinbasePrice)")
                #endif
            }
            
            // Cache and return early for precious metals
            if price > 0 {
                priceCache[upperSymbol] = (price: price, timestamp: Date())
            }
            return price
        }
        
        // PRICE CONSISTENCY: Use unified pipeline (LivePriceManager/MarketViewModel) FIRST
        // This ensures portfolio prices match Watchlist, Market, and CoinDetail pages.
        // LivePriceManager gets data from Firestore (CoinGecko synced via Firebase).
        
        // Priority 1a: MarketViewModel.bestPrice(forSymbol:) — matches by symbol (BTC, ETH, etc.)
        // FIX: Previously used bestPrice(for:) which expects a CoinGecko ID ("bitcoin"),
        // but was passed a lowercase symbol ("btc"), causing lookup failures for all coins.
        if let bestPrice = await MainActor.run(body: { MarketViewModel.shared.bestPrice(forSymbol: upperSymbol) }),
           bestPrice > 0 {
            price = bestPrice
        }
        
        // Priority 1b: Try ID-based lookup using coinID resolver (handles "BTC" -> "bitcoin" mapping)
        if price <= 0 {
            if let coinID = await MainActor.run(body: { MarketViewModel.shared.coinID(forSymbol: upperSymbol) }),
               let idPrice = await MainActor.run(body: { MarketViewModel.shared.bestPrice(for: coinID) }),
               idPrice > 0 {
                price = idPrice
            }
        }
        
        // Priority 2: LivePriceManager's Firestore-synced coins (by symbol match)
        if price <= 0 {
            let coins = await MainActor.run { LivePriceManager.shared.currentCoinsList }
            if let coin = coins.first(where: { $0.symbol.uppercased() == upperSymbol }),
               let coinPrice = coin.priceUsd, coinPrice > 0 {
                price = coinPrice
            }
        }
        
        // Priority 3: Direct exchange calls as fallback (Binance → Coinbase)
        if price <= 0 {
            do {
                let stats = try await BinanceService.fetch24hrStats(symbols: [upperSymbol])
                if let stat = stats.first, stat.lastPrice > 0 {
                    price = stat.lastPrice
                }
            } catch {
                #if DEBUG
                print("⚠️ [LivePortfolioDataService] Binance price fetch failed for \(symbol): \(error.localizedDescription)")
                #endif
            }
        }
        
        if price <= 0 {
            if let coinbasePrice = await CoinbaseService.shared.fetchSpotPrice(coin: upperSymbol), coinbasePrice > 0 {
                price = coinbasePrice
            }
        }
        
        // Cache the result if valid
        if price > 0 {
            priceCache[upperSymbol] = (price: price, timestamp: Date())
        } else if let staleCache = priceCache[upperSymbol], staleCache.price > 0 {
            // FIX: When all live sources fail, use the expired cached price instead of returning 0.
            // A stale price (even hours old) is far more useful than 0, which makes the asset
            // vanish from the portfolio total entirely. The cache TTL already ensures fresh
            // prices are preferred when available.
            #if DEBUG
            let age = Int(Date().timeIntervalSince(staleCache.timestamp))
            print("⚠️ [LivePortfolioDataService] All sources failed for \(upperSymbol). Using stale cache (\(age)s old): $\(staleCache.price)")
            #endif
            price = staleCache.price
        }
        
        return price
    }
    
    // MARK: - Coin Name Mapping
    
    private func coinName(for symbol: String) -> String {
        let names: [String: String] = [
            // Cryptocurrencies
            "BTC": "Bitcoin",
            "ETH": "Ethereum",
            "USDT": "Tether",
            "USDC": "USD Coin",
            "BNB": "BNB",
            "XRP": "XRP",
            "SOL": "Solana",
            "ADA": "Cardano",
            "DOGE": "Dogecoin",
            "TRX": "TRON",
            "DOT": "Polkadot",
            "MATIC": "Polygon",
            "LTC": "Litecoin",
            "SHIB": "Shiba Inu",
            "AVAX": "Avalanche",
            "LINK": "Chainlink",
            "ATOM": "Cosmos",
            "UNI": "Uniswap",
            "XLM": "Stellar",
            "BCH": "Bitcoin Cash",
            "NEAR": "NEAR Protocol",
            "APT": "Aptos",
            "FIL": "Filecoin",
            "ARB": "Arbitrum",
            "OP": "Optimism",
            "AAVE": "Aave",
            "CRV": "Curve DAO",
            // Precious Metals (Coinbase futures)
            "XAU": "Gold", "GOLD": "Gold", "GLD": "Gold",
            "XAG": "Silver", "SILVER": "Silver", "SLV": "Silver",
            "XPT": "Platinum", "PLATINUM": "Platinum", "PLT": "Platinum", "PLAT": "Platinum",
            "XPD": "Palladium", "PALLADIUM": "Palladium", "PAL": "Palladium",
            "XCU": "Copper", "COPPER": "Copper", "CU": "Copper", "COPR": "Copper"
        ]
        
        // First check our mapping, then check PreciousMetalsHelper for dynamic names
        if let name = names[symbol.uppercased()] {
            return name
        }
        
        // Try precious metals helper for any symbols we might have missed
        if let preciousMetalName = PreciousMetalsHelper.displayName(for: symbol) {
            return preciousMetalName
        }
        
        return symbol
    }
    
    // MARK: - Local Transaction Storage (Secure Encrypted)
    
    private func loadLocalTransactions() {
        // Load from secure encrypted storage
        localTransactions = secureDataManager.loadTransactions()
        transactionsSubject.send(localTransactions)
        
        if !localTransactions.isEmpty {
            print("🔐 Loaded \(localTransactions.count) transactions from encrypted storage")
        }
    }
    
    private func saveLocalTransactions() {
        // Save to secure encrypted storage
        secureDataManager.saveTransactions(localTransactions)
        print("🔐 Saved \(localTransactions.count) transactions to encrypted storage")
    }
    
    // MARK: - Transaction Management
    
    func addTransaction(_ tx: Transaction) {
        localTransactions.append(tx)
        saveLocalTransactions()
        transactionsSubject.send(localTransactions)
        
        // Recalculate holdings
        Task {
            await refreshHoldings()
        }
    }
    
    func updateTransaction(_ old: Transaction, with new: Transaction) {
        if let index = localTransactions.firstIndex(where: { $0.id == old.id }) {
            localTransactions[index] = new
            saveLocalTransactions()
            transactionsSubject.send(localTransactions)
            
            // Recalculate holdings
            Task {
                await refreshHoldings()
            }
        }
    }
    
    func deleteTransaction(_ tx: Transaction) {
        localTransactions.removeAll { $0.id == tx.id }
        saveLocalTransactions()
        transactionsSubject.send(localTransactions)
        
        // Recalculate holdings
        Task {
            await refreshHoldings()
        }
    }
    
    // MARK: - Force Refresh
    
    /// Force refresh ignoring cooldown
    func forceRefresh() async {
        lastRefreshTime = nil
        await refreshHoldings()
    }
}
