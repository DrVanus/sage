//
//  ConnectedAccountsManager.swift
//  CryptoSage
//
//  Manages connected exchange accounts with persistent storage.
//

import Foundation
import Combine

// MARK: - Connected Account Model

struct ConnectedAccount: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var exchangeType: String // "exchange" or "wallet"
    var provider: String // "oauth", "direct", "blockchain", "3commas"
    var isDefault: Bool
    var connectedAt: Date
    var lastSyncAt: Date?
    var accountId: Int? // 3Commas account ID if applicable
    var walletAddress: String? // For wallet connections
    
    init(
        id: String = UUID().uuidString,
        name: String,
        exchangeType: String = "exchange",
        provider: String = "direct",
        isDefault: Bool = false,
        connectedAt: Date = Date(),
        lastSyncAt: Date? = nil,
        accountId: Int? = nil,
        walletAddress: String? = nil
    ) {
        self.id = id
        self.name = name
        self.exchangeType = exchangeType
        self.provider = provider
        self.isDefault = isDefault
        self.connectedAt = connectedAt
        self.lastSyncAt = lastSyncAt
        self.accountId = accountId
        self.walletAddress = walletAddress
    }
}

// MARK: - Connected Accounts Manager

final class ConnectedAccountsManager: ObservableObject {
    static let shared = ConnectedAccountsManager()
    
    // MARK: - Published Properties
    
    @Published private(set) var accounts: [ConnectedAccount] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: String? = nil
    
    // MARK: - Secure Storage
    
    private let secureDataManager = SecureUserDataManager.shared
    
    // MARK: - Initialization
    
    private init() {
        loadAccounts()
    }
    
    // MARK: - Persistence (Now using encrypted storage)
    
    private func loadAccounts() {
        // Load from secure encrypted storage
        accounts = secureDataManager.loadConnectedAccounts()
        
        if !accounts.isEmpty {
            #if DEBUG
            print("🔐 Loaded \(accounts.count) connected accounts from encrypted storage")
            #endif
        }
    }
    
    private func saveAccounts() {
        // Save to secure encrypted storage
        secureDataManager.saveConnectedAccounts(accounts)
        #if DEBUG
        print("🔐 Saved \(accounts.count) connected accounts to encrypted storage")
        #endif
    }
    
    // MARK: - Account Management
    
    /// Check if an exchange is connected (by name)
    func isConnected(exchangeName: String) -> Bool {
        let normalizedName = exchangeName.lowercased()
        return accounts.contains { account in
            account.name.lowercased().contains(normalizedName) ||
            normalizedName.contains(account.name.lowercased())
        }
    }
    
    /// Get account by exchange name
    func account(for exchangeName: String) -> ConnectedAccount? {
        let normalizedName = exchangeName.lowercased()
        return accounts.first { account in
            account.name.lowercased().contains(normalizedName) ||
            normalizedName.contains(account.name.lowercased())
        }
    }
    
    /// Get the default account
    var defaultAccount: ConnectedAccount? {
        accounts.first { $0.isDefault } ?? accounts.first
    }
    
    /// Add a new connected account
    func addAccount(_ account: ConnectedAccount) {
        // Check for duplicates
        guard !accounts.contains(where: { $0.id == account.id }) else {
            #if DEBUG
            print("⚠️ Account already exists: \(account.name)")
            #endif
            return
        }
        
        var newAccount = account
        
        // If this is the first account, make it default
        if accounts.isEmpty {
            newAccount.isDefault = true
        }
        
        accounts.append(newAccount)
        saveAccounts()
        
        // Auto-disable demo mode when user connects real portfolio
        // Demo mode doesn't make sense when they have real data
        Task { @MainActor in
            DemoModeManager.shared.onPortfolioConnected()
        }
        
        // ANALYTICS: Track exchange connection
        AnalyticsService.shared.trackExchangeConnected(
            exchangeName: newAccount.name,
            provider: newAccount.provider
        )
        AnalyticsService.shared.updateConnectedExchangeCount(accounts.count)
        
        objectWillChange.send()
    }
    
    /// Add account from 3Commas Account model
    func addAccount(from threeCommasAccount: Account, exchangeName: String) {
        let account = ConnectedAccount(
            id: "3c-\(threeCommasAccount.id)",
            name: exchangeName,
            exchangeType: "exchange",
            provider: "3commas",
            isDefault: accounts.isEmpty,
            connectedAt: Date(),
            accountId: threeCommasAccount.id
        )
        addAccount(account)
    }
    
    /// Remove an account and clean up stored credentials
    func removeAccount(_ account: ConnectedAccount) {
        let removedName = account.name

        // Clean up credentials via the provider's disconnect method
        Task {
            do {
                let connectionType: ConnectionType = {
                    switch account.provider {
                    case "oauth": return .oauth
                    case "blockchain": return .walletAddress
                    case "3commas": return .threeCommas
                    default: return .apiKey
                    }
                }()
                if let prov = provider(for: connectionType) {
                    try await prov.disconnect(accountId: account.id)
                }
            } catch {
                #if DEBUG
                print("⚠️ [ConnectedAccounts] Failed to disconnect provider for \(account.name): \(error)")
                #endif
            }
        }

        accounts.removeAll { $0.id == account.id }

        // ANALYTICS: Track exchange disconnection
        AnalyticsService.shared.trackExchangeDisconnected(exchangeName: removedName)
        AnalyticsService.shared.updateConnectedExchangeCount(accounts.count)

        // If we removed the default, make the first remaining account default
        if account.isDefault, let first = accounts.first {
            if let index = accounts.firstIndex(where: { $0.id == first.id }) {
                accounts[index].isDefault = true
            }
        }

        saveAccounts()
        objectWillChange.send()
    }
    
    /// Remove account by ID
    func removeAccount(id: String) {
        if let account = accounts.first(where: { $0.id == id }) {
            removeAccount(account)
        }
    }
    
    /// Set an account as default
    func setAsDefault(_ account: ConnectedAccount) {
        // Clear existing default
        for i in accounts.indices {
            accounts[i].isDefault = false
        }
        
        // Set new default
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index].isDefault = true
        }
        
        saveAccounts()
        objectWillChange.send()
    }
    
    /// Rename an account
    func renameAccount(_ account: ConnectedAccount, newName: String) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index].name = newName
            saveAccounts()
            objectWillChange.send()
        }
    }
    
    /// Update last sync time
    func updateLastSync(for account: ConnectedAccount) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index].lastSyncAt = Date()
            saveAccounts()
        }
    }
    
    // MARK: - Sync with 3Commas
    
    /// Fetch and sync accounts from 3Commas (only if 3Commas credentials are configured)
    func syncWithThreeCommas() async {
        // Only sync if 3Commas is actually configured
        guard !ThreeCommasConfig.readOnlyAPIKey.isEmpty else {
            #if DEBUG
            print("ℹ️ 3Commas not configured, skipping sync")
            #endif
            return
        }
        
        await MainActor.run {
            isLoading = true
            lastError = nil
        }
        
        do {
            let threeCommasAccounts = try await ThreeCommasAPI.shared.listAccounts()
            
            await MainActor.run {
                // Add any new accounts from 3Commas
                for tcAccount in threeCommasAccounts {
                    let existingId = "3c-\(tcAccount.id)"
                    if !accounts.contains(where: { $0.id == existingId }) {
                        let account = ConnectedAccount(
                            id: existingId,
                            name: tcAccount.name ?? "3commas Account",
                            exchangeType: "exchange",
                            provider: "3commas",
                            isDefault: accounts.isEmpty,
                            connectedAt: Date(),
                            accountId: tcAccount.id
                        )
                        accounts.append(account)
                    }
                }
                saveAccounts()
                isLoading = false
            }
        } catch {
            await MainActor.run {
                lastError = "Failed to sync: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }
    
    // MARK: - Clear All
    
    /// Clear all connected accounts
    func clearAllAccounts() {
        accounts.removeAll()
        saveAccounts()
        objectWillChange.send()
    }
}

// MARK: - Account Model Extension (for 3Commas compatibility)

extension Account {
    /// Display name for the account
    var displayName: String {
        name ?? "Account \(id)"
    }
}
