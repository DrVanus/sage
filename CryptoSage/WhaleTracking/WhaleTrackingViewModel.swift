//
//  WhaleTrackingViewModel.swift
//  CryptoSage
//
//  ViewModel for whale tracking UI.
//

import Foundation
import Combine
import UIKit

@MainActor
final class WhaleTrackingViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var transactions: [WhaleTransaction] = []
    @Published var filteredTransactions: [WhaleTransaction] = []
    @Published var statistics: WhaleStatistics?
    @Published var volumeHistory: [WhaleTrackingService.VolumeDataPoint] = []
    @Published var smartMoneySignals: [SmartMoneySignal] = []
    @Published var smartMoneyIndex: SmartMoneyIndex?
    @Published var watchedWallets: [WatchedWallet] = []
    @Published var isLoading: Bool = false
    @Published var error: String?
    
    // Filters - IMPROVED: Lowered default from $500k to $100k to show more transactions
    @Published var selectedBlockchain: WhaleBlockchain? = nil
    @Published var selectedToken: String? = nil
    @Published var minAmount: Double = WhaleAlertConfig.defaultConfig.minAmountUSD
    @Published var searchText: String = ""
    @Published var sortOrder: SortOrder = .newest
    
    enum SortOrder: String, CaseIterable {
        case newest = "Newest"
        case oldest = "Oldest"
        case largest = "Largest"
        case smallest = "Smallest"
    }
    
    // Available tokens computed from transactions
    var availableTokens: [String] {
        let tokens = Set(transactions.map { $0.symbol })
        return Array(tokens).sorted()
    }
    
    // Common tokens for quick filtering
    static let commonTokens = ["ETH", "BTC", "USDT", "USDC", "SOL", "BNB", "MATIC", "AVAX", "ARB"]
    
    var baselineMinAmount: Double {
        service.config.minAmountUSD
    }
    
    // MARK: - Private Properties
    
    private let service = WhaleTrackingService.shared
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        minAmount = service.config.minAmountUSD
        setupBindings()
    }
    
    // MARK: - Public Methods
    
    func refresh() async {
        // Light haptic on pull to refresh
        let impactLight = UIImpactFeedbackGenerator(style: .light)
        impactLight.impactOccurred()
        
        // Use refresh() which bypasses rate limiting for user-initiated actions
        await service.refresh()
        
        // Success haptic when refresh completes
        let notificationGenerator = UINotificationFeedbackGenerator()
        notificationGenerator.notificationOccurred(.success)
    }
    
    func startMonitoring() {
        service.startMonitoring()
    }
    
    func stopMonitoring() {
        service.stopMonitoring()
    }
    
    func addWatchedWallet(address: String, label: String, blockchain: WhaleBlockchain) {
        let wallet = WatchedWallet(
            address: address,
            label: label,
            blockchain: blockchain
        )
        service.addWatchedWallet(wallet)
    }
    
    func removeWatchedWallet(id: UUID) {
        service.removeWatchedWallet(id: id)
    }
    
    func updateMinAmount(_ amount: Double) {
        var config = service.config
        config.minAmountUSD = amount
        service.updateConfig(config)
    }
    
    // MARK: - Private Methods
    
    private func setupBindings() {
        // Bind service data
        service.$recentTransactions
            .receive(on: DispatchQueue.main)
            .sink { [weak self] transactions in
                self?.transactions = transactions
                self?.applyFilters()
            }
            .store(in: &cancellables)
        
        service.$statistics
            .receive(on: DispatchQueue.main)
            .assign(to: &$statistics)
        
        service.$volumeHistory
            .receive(on: DispatchQueue.main)
            .assign(to: &$volumeHistory)
        
        service.$smartMoneySignals
            .receive(on: DispatchQueue.main)
            .assign(to: &$smartMoneySignals)
        
        service.$smartMoneyIndex
            .receive(on: DispatchQueue.main)
            .assign(to: &$smartMoneyIndex)
        
        service.$watchedWallets
            .receive(on: DispatchQueue.main)
            .assign(to: &$watchedWallets)
        
        service.$isLoading
            .receive(on: DispatchQueue.main)
            .assign(to: &$isLoading)
        
        service.$lastError
            .receive(on: DispatchQueue.main)
            .assign(to: &$error)
        
        service.$config
            .map(\.minAmountUSD)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] configMinAmount in
                guard let self else { return }
                if abs(self.minAmount - configMinAmount) > 0.5 {
                    self.minAmount = configMinAmount
                }
            }
            .store(in: &cancellables)
        
        $minAmount
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] amount in
                self?.syncMinAmountToService(amount)
            }
            .store(in: &cancellables)
        
        // React to filter changes - use merge for 5 publishers
        Publishers.CombineLatest4($selectedBlockchain, $minAmount, $searchText, $sortOrder)
            .combineLatest($selectedToken)
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.applyFilters()
            }
            .store(in: &cancellables)
    }
    
    private func applyFilters() {
        var filtered = transactions
        
        // Filter by blockchain
        if let blockchain = selectedBlockchain {
            filtered = filtered.filter { $0.blockchain == blockchain }
        }
        
        // Filter by token
        if let token = selectedToken {
            filtered = filtered.filter { $0.symbol.uppercased() == token.uppercased() }
        }
        
        // Filter by minimum amount
        filtered = filtered.filter { $0.amountUSD >= minAmount }
        
        // Filter by search text
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            filtered = filtered.filter {
                $0.symbol.lowercased().contains(query) ||
                $0.fromAddress.lowercased().contains(query) ||
                $0.toAddress.lowercased().contains(query) ||
                $0.hash.lowercased().contains(query)
            }
        }
        
        // Sort
        switch sortOrder {
        case .newest:
            filtered.sort { $0.timestamp > $1.timestamp }
        case .oldest:
            filtered.sort { $0.timestamp < $1.timestamp }
        case .largest:
            filtered.sort { $0.amountUSD > $1.amountUSD }
        case .smallest:
            filtered.sort { $0.amountUSD < $1.amountUSD }
        }
        
        filteredTransactions = filtered
    }
    
    // Clear all filters
    func clearFilters() {
        selectedBlockchain = nil
        selectedToken = nil
        minAmount = baselineMinAmount
        searchText = ""
        sortOrder = .newest
    }
    
    // Check if any filters are active
    var hasActiveFilters: Bool {
        selectedBlockchain != nil || selectedToken != nil || abs(minAmount - baselineMinAmount) > 0.5 || !searchText.isEmpty || sortOrder != .newest
    }
    
    private func syncMinAmountToService(_ amount: Double) {
        var config = service.config
        if abs(config.minAmountUSD - amount) <= 0.5 {
            return
        }
        config.minAmountUSD = amount
        service.updateConfig(config)
    }
}
