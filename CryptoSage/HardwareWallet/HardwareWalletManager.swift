//
//  HardwareWalletManager.swift
//  CryptoSage
//
//  Unified manager for all hardware wallet integrations.
//  SECURITY: Accounts stored in encrypted storage, not UserDefaults.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Hardware Wallet Manager

@MainActor
public final class HardwareWalletManager: ObservableObject {
    public static let shared = HardwareWalletManager()
    
    // MARK: - Published Properties
    
    @Published public private(set) var connectedWallets: [HWWalletType: Bool] = [:]
    @Published public private(set) var accounts: [HWAccount] = []
    @Published public private(set) var isConnecting = false
    @Published public private(set) var lastError: HardwareWalletError?
    @Published public private(set) var pendingSigningRequest: HWSigningRequest?
    
    // MARK: - Services
    
    public let ledgerService = LedgerService()
    public let trezorService = TrezorService()
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private let secureStorage = SecureStorage.shared
    private let accountsFileName = "hw_wallet_accounts"
    
    // MARK: - Initialization
    
    private init() {
        loadSavedAccounts()
        setupSubscriptions()
    }
    
    // MARK: - Public Methods
    
    /// Connect to a hardware wallet
    public func connect(type: HWWalletType) async throws {
        isConnecting = true
        lastError = nil
        
        do {
            switch type {
            case .ledger:
                try await ledgerService.connect()
                connectedWallets[.ledger] = true
            case .trezor:
                try await trezorService.connect()
                connectedWallets[.trezor] = true
            }
            isConnecting = false
        } catch let error as HardwareWalletError {
            lastError = error
            isConnecting = false
            throw error
        } catch {
            lastError = .unknown(error.localizedDescription)
            isConnecting = false
            throw HardwareWalletError.unknown(error.localizedDescription)
        }
    }
    
    /// Disconnect from a hardware wallet
    public func disconnect(type: HWWalletType) async {
        switch type {
        case .ledger:
            await ledgerService.disconnect()
            connectedWallets[.ledger] = false
        case .trezor:
            await trezorService.disconnect()
            connectedWallets[.trezor] = false
        }
        
        // Remove accounts from this wallet
        accounts.removeAll { $0.walletType == type }
        saveAccounts()
    }
    
    /// Disconnect from all wallets
    public func disconnectAll() async {
        await ledgerService.disconnect()
        await trezorService.disconnect()
        connectedWallets = [:]
    }
    
    /// Get accounts for a specific chain
    public func getAccounts(for chain: Chain, walletType: HWWalletType? = nil) async throws -> [HWAccount] {
        var fetchedAccounts: [HWAccount] = []
        
        if walletType == nil || walletType == .ledger {
            if ledgerService.isConnected && ledgerService.supportedChains.contains(chain) {
                let ledgerAccounts = try await ledgerService.getAccounts(for: chain)
                fetchedAccounts.append(contentsOf: ledgerAccounts)
            }
        }
        
        if walletType == nil || walletType == .trezor {
            if trezorService.isConnected && trezorService.supportedChains.contains(chain) {
                let trezorAccounts = try await trezorService.getAccounts(for: chain)
                fetchedAccounts.append(contentsOf: trezorAccounts)
            }
        }
        
        // Update stored accounts
        for account in fetchedAccounts {
            if !accounts.contains(where: { $0.id == account.id }) {
                accounts.append(account)
            }
        }
        saveAccounts()
        
        return fetchedAccounts
    }
    
    /// Import an account manually
    public func importAccount(_ account: HWAccount) {
        if !accounts.contains(where: { $0.id == account.id }) {
            accounts.append(account)
            saveAccounts()
        }
    }
    
    /// Remove an account
    public func removeAccount(_ account: HWAccount) {
        accounts.removeAll { $0.id == account.id }
        saveAccounts()
        
        // Also remove from specific service
        if account.walletType == .trezor {
            trezorService.removeAccount(account)
        }
    }
    
    /// Sign a message with a hardware wallet
    public func signMessage(_ message: Data, account: HWAccount) async throws -> Data {
        // Create signing request for UI
        let displayInfo = HWSigningDisplayInfo(
            title: "Sign Message",
            subtitle: "Review on your \(account.walletType.displayName)",
            details: [
                ("Account", account.shortAddress),
                ("Chain", account.chain.displayName)
            ]
        )
        
        pendingSigningRequest = HWSigningRequest(
            account: account,
            requestType: .message(message),
            displayInfo: displayInfo
        )
        
        defer { pendingSigningRequest = nil }
        
        switch account.walletType {
        case .ledger:
            return try await ledgerService.signMessage(message, account: account)
        case .trezor:
            return try await trezorService.signMessage(message, account: account)
        }
    }
    
    /// Sign typed data (EIP-712) with a hardware wallet
    public func signTypedData(_ typedData: HWTypedData, account: HWAccount) async throws -> Data {
        let displayInfo = HWSigningDisplayInfo(
            title: "Sign Typed Data",
            subtitle: "Review on your \(account.walletType.displayName)",
            details: [
                ("Account", account.shortAddress),
                ("Type", typedData.primaryType)
            ]
        )
        
        pendingSigningRequest = HWSigningRequest(
            account: account,
            requestType: .typedData(typedData),
            displayInfo: displayInfo
        )
        
        defer { pendingSigningRequest = nil }
        
        switch account.walletType {
        case .ledger:
            return try await ledgerService.signTypedData(typedData, account: account)
        case .trezor:
            return try await trezorService.signTypedData(typedData, account: account)
        }
    }
    
    /// Sign a transaction with a hardware wallet
    public func signTransaction(_ transaction: HWTransaction, account: HWAccount) async throws -> Data {
        let displayInfo = HWSigningDisplayInfo(
            title: "Sign Transaction",
            subtitle: "Review on your \(account.walletType.displayName)",
            details: [
                ("From", account.shortAddress),
                ("To", String(transaction.to.prefix(10)) + "..."),
                ("Value", transaction.value),
                ("Chain", account.chain.displayName)
            ],
            warningMessage: transaction.data != nil ? "This transaction contains contract data" : nil
        )
        
        pendingSigningRequest = HWSigningRequest(
            account: account,
            requestType: .transaction(transaction),
            displayInfo: displayInfo
        )
        
        defer { pendingSigningRequest = nil }
        
        switch account.walletType {
        case .ledger:
            return try await ledgerService.signTransaction(transaction, account: account)
        case .trezor:
            return try await trezorService.signTransaction(transaction, account: account)
        }
    }
    
    /// Check if any hardware wallet is connected
    public var hasConnectedWallet: Bool {
        ledgerService.isConnected || trezorService.isConnected
    }
    
    /// Get all connected wallet types
    public var connectedWalletTypes: [HWWalletType] {
        var types: [HWWalletType] = []
        if ledgerService.isConnected { types.append(.ledger) }
        if trezorService.isConnected { types.append(.trezor) }
        return types
    }
    
    /// Get accounts for a wallet type
    public func accounts(for walletType: HWWalletType) -> [HWAccount] {
        accounts.filter { $0.walletType == walletType }
    }
    
    /// Get accounts for a chain
    public func accounts(for chain: Chain) -> [HWAccount] {
        accounts.filter { $0.chain == chain }
    }
    
    // MARK: - Private Methods
    
    private func setupSubscriptions() {
        // Monitor Ledger connection state
        ledgerService.$isConnected
            .sink { [weak self] connected in
                self?.connectedWallets[.ledger] = connected
            }
            .store(in: &cancellables)
        
        // Monitor Trezor connection state
        trezorService.$isConnected
            .sink { [weak self] connected in
                self?.connectedWallets[.trezor] = connected
            }
            .store(in: &cancellables)
        
        // Monitor errors
        ledgerService.$lastError
            .compactMap { $0 }
            .sink { [weak self] error in
                self?.lastError = error
            }
            .store(in: &cancellables)
        
        trezorService.$lastError
            .compactMap { $0 }
            .sink { [weak self] error in
                self?.lastError = error
            }
            .store(in: &cancellables)
    }
    
    private func loadSavedAccounts() {
        // Load from encrypted storage (not UserDefaults - wallet addresses are sensitive)
        if let savedAccounts = secureStorage.loadEncrypted([HWAccount].self, from: accountsFileName) {
            accounts = savedAccounts
            print("🔐 [HWWallet] Loaded \(accounts.count) accounts from encrypted storage")
        }
        
        // Migrate from old UserDefaults storage if exists
        let legacyKey = "hw_accounts"
        if let legacyData = UserDefaults.standard.data(forKey: legacyKey),
           let legacyAccounts = try? JSONDecoder().decode([HWAccount].self, from: legacyData) {
            // Merge with any existing accounts
            for account in legacyAccounts {
                if !accounts.contains(where: { $0.id == account.id }) {
                    accounts.append(account)
                }
            }
            saveAccounts()
            UserDefaults.standard.removeObject(forKey: legacyKey)
            print("🔐 [HWWallet] Migrated accounts from UserDefaults to encrypted storage")
        }
    }
    
    private func saveAccounts() {
        // Save to encrypted storage for security
        secureStorage.saveEncrypted(accounts, to: accountsFileName)
    }
    
    /// Clear all hardware wallet accounts (for security reset)
    public func clearAllAccounts() {
        accounts.removeAll()
        secureStorage.deleteEncrypted(accountsFileName)
        print("🔐 [HWWallet] All accounts cleared")
    }
}

// MARK: - Convenience Extensions

public extension HardwareWalletManager {
    /// Quick check if a specific wallet type is connected
    func isConnected(_ type: HWWalletType) -> Bool {
        switch type {
        case .ledger: return ledgerService.isConnected
        case .trezor: return trezorService.isConnected
        }
    }
    
    /// Get the service for a wallet type
    func service(for type: HWWalletType) -> any HardwareWalletProvider {
        switch type {
        case .ledger: return ledgerService
        case .trezor: return trezorService
        }
    }
    
    /// Get connection state for a wallet type
    func connectionState(for type: HWWalletType) -> HWConnectionState {
        switch type {
        case .ledger: return ledgerService.connectionState
        case .trezor: return trezorService.connectionState
        }
    }
}
