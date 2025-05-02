import SwiftUI
import Combine
import Foundation

/// Encodable model combining holdings and transactions for AI insights
struct Portfolio: Encodable {
    let holdings: [Holding]
    let transactions: [Transaction]
}


// MARK: - Sample Data for Previews
extension PortfolioViewModel {
    /// A sample instance with demo holdings for SwiftUI previews and Debug builds.
    static let sample: PortfolioViewModel = {
        let manualService = ManualPortfolioDataService(initialHoldings: [], initialTransactions: [])
        let liveService = LivePortfolioDataService()
        let priceService = CoinGeckoPriceService()
        let repository = PortfolioRepository(
            manualService: manualService,
            liveService: liveService,
            priceService: priceService
        )
        let vm = PortfolioViewModel(repository: repository)
        // Override holdings to match demo values
        vm.holdings = [
            // 50 BTC at $100,000 = $5,000,000
            Holding(coinName: "Bitcoin", coinSymbol: "BTC", quantity: 50, currentPrice: 100_000, costBasis: 50_000, imageUrl: nil, isFavorite: true, dailyChange: 1.2, purchaseDate: Date()),
            // 200 ETH at $2,500 = $500,000
            Holding(coinName: "Ethereum", coinSymbol: "ETH", quantity: 200, currentPrice: 2_500, costBasis: 1_800, imageUrl: nil, isFavorite: false, dailyChange: -0.8, purchaseDate: Date()),
            // 10,000 SOL at $400 = $4,000,000
            Holding(coinName: "Solana", coinSymbol: "SOL", quantity: 10_000, currentPrice: 400, costBasis: 100, imageUrl: nil, isFavorite: false, dailyChange: 2.5, purchaseDate: Date()),
            // 1,000,000 XRP at $1 = $1,000,000
            Holding(coinName: "XRP", coinSymbol: "XRP", quantity: 1_000_000, currentPrice: 1, costBasis: 0.5, imageUrl: nil, isFavorite: false, dailyChange: 0.3, purchaseDate: Date())
        ]
        // Optionally clear or set demo transactions
        vm.transactions = []
        // Build a mock history where yesterday’s total was 2% lower than today
        let today = Date()
        let previousValue = vm.totalValue * 0.98
        var mockPoints: [ChartPoint] = []
        for daysAgo in 0...30 {
            let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: today)!
            let value = (daysAgo == 0) ? vm.totalValue : previousValue
            mockPoints.append(ChartPoint(date: date, value: value))
        }
        vm.history = mockPoints
        return vm
    }()
}

// MARK: - Chart Data Model
struct ChartPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}


// MARK: - Color Mapping for Pie Charts
extension PortfolioViewModel {
    /// Returns the chart color associated with a given coin symbol.
    func color(for symbol: String) -> Color {
        switch symbol {
        case "BTC":
            return .blue
        case "ETH":
            return .green
        case "SOL":
            return .orange
        default:
            return .gray
        }
    }
}


// MARK: - Formatters for Signed Values
private extension PortfolioViewModel {
    /// Formatter for signed percent (e.g. "+1.23%", "−0.45%")
    static let percentFormatter: NumberFormatter = {
        let fmt = NumberFormatter()
        fmt.numberStyle = .percent
        fmt.minimumFractionDigits = 2
        fmt.maximumFractionDigits = 2
        fmt.positivePrefix = "+"
        fmt.negativePrefix = "−"
        return fmt
    }()

    /// Formatter for signed currency (e.g. "+$1,234.56", "−$987.65")
    static let signedCurrencyFormatter: NumberFormatter = {
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.minimumFractionDigits = 2
        fmt.maximumFractionDigits = 2
        let symbol = fmt.currencySymbol ?? "$"
        fmt.positivePrefix = "+" + symbol
        fmt.negativePrefix = "−" + symbol
        return fmt
    }()
}

// MARK: - Computed Metrics
extension PortfolioViewModel {
    /// 24h percentage change based on previous total value
    var dailyChangePercent: Double {
        // TODO: Replace `previousTotalValue` with actual logic to fetch yesterday's total
        let previousTotalValue = history.first(where: { Calendar.current.isDate($0.date, inSameDayAs: Calendar.current.date(byAdding: .day, value: -1, to: Date())!) })?.value ?? totalValue
        guard previousTotalValue != 0 else { return 0 }
        return (totalValue - previousTotalValue) / previousTotalValue * 100
    }

    /// Formatted daily change percent string (e.g. "+1.23%")
    var dailyChangePercentString: String {
        return Self.percentFormatter.string(from: NSNumber(value: dailyChangePercent / 100)) ?? "0.00%"
    }

    /// Unrealized profit/loss (current total minus cost basis of holdings)
    var unrealizedPL: Double {
        // Sum of (currentValue - costBasis * quantity) for each holding
        holdings.reduce(0) { result, holding in
            let cost = holding.costBasis * holding.quantity
            return result + (holding.currentValue - cost)
        }
    }

    /// Formatted unrealized P/L string (e.g. "+$123.45")
    var unrealizedPLString: String {
        return Self.signedCurrencyFormatter.string(from: NSNumber(value: unrealizedPL)) ?? "$0.00"
    }
}

// MARK: - Allocation Data for Charts
extension PortfolioViewModel {
    /// Represents one slice of the portfolio allocation for charting.
    struct AllocationSlice: Identifiable {
        let id = UUID()
        let symbol: String
        let percent: Double
        let color: Color
    }

    /// Breaks holdings into percentage slices for the donut chart.
    var allocationData: [AllocationSlice] {
        let total = totalValue
        return holdings.map { position in
            AllocationSlice(
                symbol: position.coinSymbol,
                percent: total > 0 ? (position.currentValue / total) * 100 : 0,
                color: color(for: position.coinSymbol)
            )
        }
    }
}

class PortfolioViewModel: ObservableObject {
    // MARK: - Persistence URL
    private let transactionsFileURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("transactions.json")
    }()

    // Repository providing unified holdings (manual, synced, live-priced)
    private let repository: PortfolioRepository

    // Combine cancellables
    private var cancellables = Set<AnyCancellable>()

    /// Initialize with a repository providing unified holdings.
    init(repository: PortfolioRepository) {
        self.repository = repository

        // Subscribe to combined/live holdings from repository
        repository.holdingsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newHoldings in
                self?.holdings = newHoldings
                self?.loadHistory()
            }
            .store(in: &cancellables)

        // Load any persisted manual transactions
        loadTransactions()

        // Start polling live prices and update holdings
        LivePriceManager.shared.startPolling()
        LivePriceManager.shared.coinsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] marketCoins in
                guard let self = self else { return }
                // Update each holding’s currentPrice and dailyChange based on market data
                self.holdings = self.holdings.map { holding in
                    if let coin = marketCoins.first(where: { $0.symbol.uppercased() == holding.coinSymbol.uppercased() }) {
                        return Holding(
                            coinName: holding.coinName,
                            coinSymbol: holding.coinSymbol,
                            quantity: holding.quantity,
                            currentPrice: coin.priceUsd ?? 0.0,
                            costBasis: holding.costBasis,
                            imageUrl: holding.imageUrl,
                            isFavorite: holding.isFavorite,
                            dailyChange: coin.dailyChange,
                            purchaseDate: holding.purchaseDate
                        )
                    } else {
                        return holding
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Published Properties
    @Published var holdings: [Holding] = []
    @Published var history: [ChartPoint] = []
    @Published var highlightedDate: Date? = nil
    @Published var transactions: [Transaction] = []
    @Published var editingTransaction: Transaction? = nil

    /// Combined portfolio data for AIInsightService
    var portfolio: Portfolio {
        Portfolio(holdings: holdings, transactions: transactions)
    }

    // Computed property for total portfolio value.
    var totalValue: Double {
        holdings.reduce(0) { $0 + $1.currentValue }
    }
    
    // MARK: - Transaction and Holding Management
    
    /// Removes a holding at the given index set.
    func removeHolding(at indexSet: IndexSet) {
        holdings.remove(atOffsets: indexSet)
    }
    
    // Removed the old version of deleteManualTransaction(_:)
    
    // MARK: - NEW: Add a Holding
    
    /// Creates and appends a new Holding to the array, matching what AddHoldingView calls.
    func addHolding(
        coinName: String,
        coinSymbol: String,
        quantity: Double,
        currentPrice: Double,
        costBasis: Double,
        imageUrl: String?,
        purchaseDate: Date
    ) {
        let newHolding = Holding(
            coinName: coinName,
            coinSymbol: coinSymbol,
            quantity: quantity,
            currentPrice: currentPrice,
            costBasis: costBasis,
            imageUrl: imageUrl,
            isFavorite: false,    // default to not-favorite
            dailyChange: 0.0,     // or fetch real data if available
            purchaseDate: purchaseDate
        )
        
        holdings.append(newHolding)
    }
    
    // MARK: - NEW: Toggle Favorite
    
    /// Toggles the isFavorite flag on a specific holding.
    func toggleFavorite(_ holding: Holding) {
        guard let index = holdings.firstIndex(where: { $0.id == holding.id }) else { return }
        holdings[index].isFavorite.toggle()
    }
}

// MARK: - Top/Worst Performers
extension PortfolioViewModel {
    /// Formatted string for the top 24h performer (e.g., "BTC +4.2%")
    var topPerformerString: String {
        guard let top = holdings.max(by: { $0.dailyChangePercent < $1.dailyChangePercent }) else { return "--" }
        let sign = top.dailyChangePercent >= 0 ? "+" : ""
        return "\(top.coinSymbol) \(sign)\(String(format: "%.1f", top.dailyChangePercent))%"
    }

    /// Formatted string for the worst 24h performer (e.g., "DOGE -3.5%")
    var worstPerformerString: String {
        guard let worst = holdings.min(by: { $0.dailyChangePercent < $1.dailyChangePercent }) else { return "--" }
        let sign = worst.dailyChangePercent >= 0 ? "+" : ""
        return "\(worst.coinSymbol) \(sign)\(String(format: "%.1f", worst.dailyChangePercent))%"
    }
}

// MARK: - Transaction & Portfolio Management
extension PortfolioViewModel {
    /// Adds a transaction and updates the corresponding holding.
    func addTransaction(_ transaction: Transaction) {
        transactions.append(transaction)
        updateHolding(with: transaction)
        saveTransactions()
    }
    
    /// Updates or creates a holding based on a transaction.
    private func updateHolding(with transaction: Transaction) {
        // Try to find an existing holding by coin symbol (case-insensitive).
        if let index = holdings.firstIndex(where: { $0.coinSymbol.uppercased() == transaction.coinSymbol.uppercased() }) {
            var holding = holdings[index]
            
            if transaction.isBuy {
                // For a buy, calculate the new total cost and quantity, then update the average cost basis.
                let currentTotalCost = holding.costBasis * holding.quantity
                let transactionCost = transaction.pricePerUnit * transaction.quantity
                let newQuantity = holding.quantity + transaction.quantity
                let newCostBasis = newQuantity > 0 ? (currentTotalCost + transactionCost) / newQuantity : 0
                
                holding.quantity = newQuantity
                holding.costBasis = newCostBasis
            } else {
                // For a sell, subtract the sold quantity from the holding.
                holding.quantity -= transaction.quantity
                // If holding.quantity <= 0, consider removing it or resetting cost basis.
            }
            
            holdings[index] = holding
        } else {
            // No existing holding found.
            if transaction.isBuy {
                // Create a new holding for a buy transaction.
                let newHolding = Holding(
                    // We don't have transaction.coinName, so reuse coinSymbol as coinName for now.
                    coinName: transaction.coinSymbol,
                    coinSymbol: transaction.coinSymbol,
                    quantity: transaction.quantity,
                    currentPrice: transaction.pricePerUnit,  // Placeholder; update as needed
                    costBasis: transaction.pricePerUnit,
                    imageUrl: nil,
                    isFavorite: false,
                    dailyChange: 0.0,
                    purchaseDate: transaction.date
                )
                holdings.append(newHolding)
            } else {
                // Correctly formatted error message:
                print("Error: Trying to sell a coin that doesn't exist in holdings.")
            }
        }
    }
}

// MARK: - Transaction Editing & Recalculation
extension PortfolioViewModel {
    /// Recalculates holdings from all transactions.
    private func recalcHoldingsFromAllTransactions() {
        // Clear current holdings
        holdings.removeAll()
        
        // Optional: Sort transactions by date if order matters
        let sortedTransactions = transactions.sorted { $0.date < $1.date }
        
        // Reapply each transaction
        for tx in sortedTransactions {
            updateHolding(with: tx)
        }
    }
    
    /// Updates an existing manual transaction.
    func updateTransaction(oldTx: Transaction, newTx: Transaction) {
        // Only allow editing of manual transactions
        guard oldTx.isManual else {
            print("Error: Cannot update an exchange transaction.")
            return
        }
        
        if let index = transactions.firstIndex(where: { $0.id == oldTx.id }) {
            transactions[index] = newTx
        } else {
            print("Error: Transaction not found.")
        }
        
        recalcHoldingsFromAllTransactions()
        saveTransactions()
    }
    
    /// Deletes a manual transaction and recalculates holdings.
    func deleteManualTransaction(_ tx: Transaction) {
        // Only allow deletion of manual transactions
        guard tx.isManual else {
            print("Error: Cannot delete an exchange transaction.")
            return
        }
        
        if let index = transactions.firstIndex(where: { $0.id == tx.id }) {
            transactions.remove(at: index)
        } else {
            print("Error: Transaction not found.")
        }
        
        recalcHoldingsFromAllTransactions()
        saveTransactions()
    }
}

// MARK: - Persistence
extension PortfolioViewModel {
    /// Loads saved transactions from disk.
    private func loadTransactions() {
        // Check if the file exists; if not, initialize with an empty array
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: transactionsFileURL.path) {
            self.transactions = []
            return
        }

        do {
            let data = try Data(contentsOf: transactionsFileURL)
            let decoded = try JSONDecoder().decode([Transaction].self, from: data)
            self.transactions = decoded
        } catch {
            print("Failed to load transactions:", error)
            self.transactions = []
        }
    }

    /// Saves current transactions to disk.
    private func saveTransactions() {
        do {
            let data = try JSONEncoder().encode(transactions)
            try data.write(to: transactionsFileURL, options: [.atomic])
        } catch {
            print("Failed to save transactions:", error)
        }
    }
    
    /// Builds a time-series of portfolio total value for the past 30 days based on transactions.
    func loadHistory() {
        var points: [ChartPoint] = []
        // Sort transactions chronologically
        let sortedTx = transactions.sorted { $0.date < $1.date }
        
        // Calculate holdings as of each date
        for daysAgo in stride(from: 30, through: 0, by: -1) {
            guard let targetDate = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) else { continue }
            
            // Track quantity and cost basis per symbol
            var holdingsAtDate: [String: (quantity: Double, costBasis: Double)] = [:]
            
            for tx in sortedTx where tx.date <= targetDate {
                let symbol = tx.coinSymbol
                var record = holdingsAtDate[symbol] ?? (0, 0)
                
                if tx.isBuy {
                    let totalCost = record.costBasis * record.quantity + tx.pricePerUnit * tx.quantity
                    let newQty = record.quantity + tx.quantity
                    let newCostBasis = newQty > 0 ? totalCost / newQty : 0
                    record = (newQty, newCostBasis)
                } else {
                    let newQty = record.quantity - tx.quantity
                    record = (newQty, record.costBasis)
                }
                
                holdingsAtDate[symbol] = record
            }
            
            // Compute total value using costBasis as proxy for price
            let valueAtDate = holdingsAtDate.values.reduce(0) { acc, rec in
                acc + (rec.quantity * rec.costBasis)
            }
            
            points.append(ChartPoint(date: targetDate, value: valueAtDate))
        }
        
        history = points
    }
}
