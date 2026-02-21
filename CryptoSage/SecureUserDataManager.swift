//
//  SecureUserDataManager.swift
//  CryptoSage
//
//  Comprehensive secure data management for all user data.
//  Implements security practices used by professional exchanges like Coinbase and Binance.
//
//  Security Levels:
//  - PUBLIC: Non-sensitive preferences (stored in UserDefaults)
//  - SENSITIVE: Portfolio data, transactions, accounts (encrypted local storage)
//  - SECRET: API keys, passwords, private keys (Apple Keychain only)
//

import Foundation
import CryptoKit
import Combine

// MARK: - Data Security Level

enum DataSecurityLevel {
    case publicData      // UserDefaults - app preferences, UI settings
    case sensitiveData   // Encrypted files - portfolio, transactions, accounts
    case secretData      // Keychain only - API keys, secrets, private keys
}

// MARK: - Secure User Data Manager

/// Central manager for all user data with appropriate security levels
/// Follows best practices from professional crypto exchanges
final class SecureUserDataManager: ObservableObject {
    static let shared = SecureUserDataManager()
    
    // MARK: - Storage
    
    private let secureStorage = SecureStorage.shared
    private let keychainService = "CryptoSage.UserData"
    
    // MARK: - File Names for Encrypted Storage
    
    private enum SecureFileName: String {
        case transactions = "user_transactions"
        case connectedAccounts = "connected_accounts"
        case portfolioSettings = "portfolio_settings"
        case chatHistory = "chat_history"
        case walletData = "wallet_data"
        case tradingPreferences = "trading_preferences"
    }
    
    // MARK: - Published State
    
    @Published private(set) var isDataLoaded: Bool = false
    @Published private(set) var lastSaveError: String?
    
    // MARK: - Cached Data (decrypted in memory only)
    
    private var cachedTransactions: [Transaction]?
    private var cachedAccounts: [ConnectedAccount]?
    
    private init() {
        // Migrate from UserDefaults on first run
        migrateFromUserDefaultsIfNeeded()
    }
    
    // MARK: - Migration from UserDefaults
    
    /// Migrate existing data from UserDefaults to encrypted storage
    private func migrateFromUserDefaultsIfNeeded() {
        let migrationKey = "SecureUserData.MigrationComplete.v2"
        
        guard !UserDefaults.standard.bool(forKey: migrationKey) else {
            isDataLoaded = true
            return
        }
        
        print("🔐 [SecureUserDataManager] Migrating user data to encrypted storage...")
        
        // Migrate transactions
        if let txData = UserDefaults.standard.data(forKey: "CryptoSage.ManualTransactions") {
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let transactions = try decoder.decode([Transaction].self, from: txData)
                saveTransactions(transactions)
                UserDefaults.standard.removeObject(forKey: "CryptoSage.ManualTransactions")
                print("✅ Migrated \(transactions.count) transactions to encrypted storage")
            } catch {
                print("⚠️ Failed to migrate transactions: \(error)")
            }
        }
        
        // Migrate connected accounts
        if let accData = UserDefaults.standard.data(forKey: "CryptoSage.ConnectedAccounts") {
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let accounts = try decoder.decode([ConnectedAccount].self, from: accData)
                saveConnectedAccounts(accounts)
                UserDefaults.standard.removeObject(forKey: "CryptoSage.ConnectedAccounts")
                print("✅ Migrated \(accounts.count) connected accounts to encrypted storage")
            } catch {
                print("⚠️ Failed to migrate connected accounts: \(error)")
            }
        }
        
        UserDefaults.standard.set(true, forKey: migrationKey)
        isDataLoaded = true
        print("🔐 [SecureUserDataManager] Migration complete")
    }
    
    // MARK: - Transactions (SENSITIVE)
    
    /// Save transactions to encrypted storage
    func saveTransactions(_ transactions: [Transaction]) {
        cachedTransactions = transactions
        secureStorage.saveEncrypted(transactions, to: SecureFileName.transactions.rawValue)
    }
    
    /// Load transactions from encrypted storage
    func loadTransactions() -> [Transaction] {
        if let cached = cachedTransactions {
            return cached
        }
        
        if let transactions = secureStorage.loadEncrypted([Transaction].self, from: SecureFileName.transactions.rawValue) {
            cachedTransactions = transactions
            return transactions
        }
        
        return []
    }
    
    /// Add a single transaction
    func addTransaction(_ transaction: Transaction) {
        var transactions = loadTransactions()
        transactions.append(transaction)
        saveTransactions(transactions)
    }
    
    /// Delete a transaction
    func deleteTransaction(_ transaction: Transaction) {
        var transactions = loadTransactions()
        transactions.removeAll { $0.id == transaction.id }
        saveTransactions(transactions)
    }
    
    /// Update a transaction
    func updateTransaction(_ old: Transaction, with new: Transaction) {
        var transactions = loadTransactions()
        if let index = transactions.firstIndex(where: { $0.id == old.id }) {
            transactions[index] = new
            saveTransactions(transactions)
        }
    }
    
    // MARK: - Connected Accounts (SENSITIVE)
    
    /// Save connected accounts to encrypted storage
    func saveConnectedAccounts(_ accounts: [ConnectedAccount]) {
        cachedAccounts = accounts
        secureStorage.saveEncrypted(accounts, to: SecureFileName.connectedAccounts.rawValue)
    }
    
    /// Load connected accounts from encrypted storage
    func loadConnectedAccounts() -> [ConnectedAccount] {
        if let cached = cachedAccounts {
            return cached
        }
        
        if let accounts = secureStorage.loadEncrypted([ConnectedAccount].self, from: SecureFileName.connectedAccounts.rawValue) {
            cachedAccounts = accounts
            return accounts
        }
        
        return []
    }
    
    /// Add a connected account
    func addConnectedAccount(_ account: ConnectedAccount) {
        var accounts = loadConnectedAccounts()
        accounts.append(account)
        saveConnectedAccounts(accounts)
    }
    
    /// Remove a connected account
    func removeConnectedAccount(_ account: ConnectedAccount) {
        var accounts = loadConnectedAccounts()
        accounts.removeAll { $0.id == account.id }
        saveConnectedAccounts(accounts)
    }
    
    // MARK: - Wallet Data (SENSITIVE)
    
    /// Wallet connection info (NOT private keys - those go in Keychain)
    struct WalletInfo: Codable {
        let address: String
        let chain: String
        let label: String?
        let connectedAt: Date
    }
    
    /// Save wallet info to encrypted storage
    func saveWalletInfo(_ wallets: [WalletInfo]) {
        secureStorage.saveEncrypted(wallets, to: SecureFileName.walletData.rawValue)
    }
    
    /// Load wallet info from encrypted storage
    func loadWalletInfo() -> [WalletInfo] {
        return secureStorage.loadEncrypted([WalletInfo].self, from: SecureFileName.walletData.rawValue) ?? []
    }
    
    // MARK: - Chat History (SENSITIVE - may contain financial info)
    
    struct ChatMessage: Codable {
        let id: UUID
        let role: String // "user" or "assistant"
        let content: String
        let timestamp: Date
    }
    
    /// Save chat history to encrypted storage
    func saveChatHistory(_ messages: [ChatMessage]) {
        secureStorage.saveEncrypted(messages, to: SecureFileName.chatHistory.rawValue)
    }
    
    /// Load chat history from encrypted storage
    func loadChatHistory() -> [ChatMessage] {
        return secureStorage.loadEncrypted([ChatMessage].self, from: SecureFileName.chatHistory.rawValue) ?? []
    }
    
    /// Clear chat history
    func clearChatHistory() {
        secureStorage.deleteEncrypted(SecureFileName.chatHistory.rawValue)
    }
    
    // MARK: - API Keys (SECRET - Keychain Only)
    
    /// Save API key to Keychain (SECRET level)
    func saveAPIKey(_ key: String, for service: String) throws {
        let sanitized = APIKeyValidator.sanitize(key)
        try KeychainHelper.shared.save(sanitized, service: keychainService, account: "apikey_\(service)")
    }
    
    /// Load API key from Keychain
    func loadAPIKey(for service: String) -> String? {
        return try? KeychainHelper.shared.read(service: keychainService, account: "apikey_\(service)")
    }
    
    /// Delete API key from Keychain
    func deleteAPIKey(for service: String) {
        try? KeychainHelper.shared.delete(service: keychainService, account: "apikey_\(service)")
    }
    
    /// Save API secret to Keychain (SECRET level)
    func saveAPISecret(_ secret: String, for service: String) throws {
        let sanitized = APIKeyValidator.sanitize(secret)
        try KeychainHelper.shared.save(sanitized, service: keychainService, account: "apisecret_\(service)")
    }
    
    /// Load API secret from Keychain
    func loadAPISecret(for service: String) -> String? {
        return try? KeychainHelper.shared.read(service: keychainService, account: "apisecret_\(service)")
    }
    
    /// Delete API secret from Keychain
    func deleteAPISecret(for service: String) {
        try? KeychainHelper.shared.delete(service: keychainService, account: "apisecret_\(service)")
    }
    
    // MARK: - Export & Backup
    
    /// Export portfolio data (encrypted) for backup
    /// Returns encrypted data that can only be decrypted on this device
    func exportPortfolioBackup() -> Data? {
        struct BackupData: Codable {
            let transactions: [Transaction]
            let accounts: [ConnectedAccount]
            let wallets: [WalletInfo]
            let exportDate: Date
            let appVersion: String
        }
        
        let backup = BackupData(
            transactions: loadTransactions(),
            accounts: loadConnectedAccounts(),
            wallets: loadWalletInfo(),
            exportDate: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        )
        
        do {
            let data = try JSONEncoder().encode(backup)
            return secureStorage.encrypt(data)
        } catch {
            lastSaveError = "Failed to create backup: \(error.localizedDescription)"
            return nil
        }
    }
    
    /// Import portfolio data from backup
    /// Only works with backups from this device (encryption key is device-specific)
    func importPortfolioBackup(_ encryptedData: Data) -> Bool {
        struct BackupData: Codable {
            let transactions: [Transaction]
            let accounts: [ConnectedAccount]
            let wallets: [WalletInfo]
            let exportDate: Date
            let appVersion: String
        }
        
        guard let decrypted = secureStorage.decrypt(encryptedData) else {
            lastSaveError = "Failed to decrypt backup (wrong device or corrupted data)"
            return false
        }
        
        do {
            let backup = try JSONDecoder().decode(BackupData.self, from: decrypted)
            saveTransactions(backup.transactions)
            saveConnectedAccounts(backup.accounts)
            saveWalletInfo(backup.wallets)
            return true
        } catch {
            lastSaveError = "Failed to restore backup: \(error.localizedDescription)"
            return false
        }
    }
    
    // MARK: - Data Wipe
    
    /// Securely delete all user data
    func wipeAllData() {
        // Clear encrypted files
        secureStorage.deleteEncrypted(SecureFileName.transactions.rawValue)
        secureStorage.deleteEncrypted(SecureFileName.connectedAccounts.rawValue)
        secureStorage.deleteEncrypted(SecureFileName.walletData.rawValue)
        secureStorage.deleteEncrypted(SecureFileName.chatHistory.rawValue)
        secureStorage.deleteEncrypted(SecureFileName.portfolioSettings.rawValue)
        secureStorage.deleteEncrypted(SecureFileName.tradingPreferences.rawValue)
        
        // Clear caches
        cachedTransactions = nil
        cachedAccounts = nil
        
        // Note: Keychain items are NOT deleted - user must explicitly remove API keys
        
        print("🗑️ [SecureUserDataManager] All encrypted user data wiped")
    }
    
    /// Securely delete ALL data including Keychain
    func wipeAllDataIncludingSecrets() {
        wipeAllData()
        
        // Common service names used for API keys
        let services = ["binance", "coinbase", "3commas", "openai", "kraken", "kucoin"]
        for service in services {
            deleteAPIKey(for: service)
            deleteAPISecret(for: service)
        }
        
        // Clear the main API config keys
        APIConfig.removeOpenAIKey()
        try? KeychainHelper.shared.delete(service: "CryptoSage.3Commas", account: "api_key")
        try? KeychainHelper.shared.delete(service: "CryptoSage.3Commas", account: "api_secret")
        try? KeychainHelper.shared.delete(service: "3Commas", account: "trading_key")
        try? KeychainHelper.shared.delete(service: "3Commas", account: "trading_secret")
        
        #if DEBUG
        print("🗑️ [SecureUserDataManager] All data including secrets wiped")
        #endif
    }
    
    // MARK: - Cache Management
    
    /// Clear in-memory caches (call when app goes to background for extra security)
    func clearMemoryCaches() {
        cachedTransactions = nil
        cachedAccounts = nil
    }
}

// MARK: - Security Best Practices Documentation
/*
 
 ╔═══════════════════════════════════════════════════════════════════════════════╗
 ║                    CRYPTOSAGE SECURITY ARCHITECTURE                           ║
 ╠═══════════════════════════════════════════════════════════════════════════════╣
 ║                                                                               ║
 ║  This follows security practices used by professional exchanges:              ║
 ║                                                                               ║
 ║  ┌─────────────────────────────────────────────────────────────────────────┐  ║
 ║  │                          SECRET (Keychain)                              │  ║
 ║  │  • API Keys & Secrets                                                   │  ║
 ║  │  • Private Keys (if wallet features added)                              │  ║
 ║  │  • Encryption Master Key                                                │  ║
 ║  │  • Hardware-backed security on supported devices                        │  ║
 ║  └─────────────────────────────────────────────────────────────────────────┘  ║
 ║                                    ▲                                          ║
 ║                                    │                                          ║
 ║  ┌─────────────────────────────────────────────────────────────────────────┐  ║
 ║  │                      SENSITIVE (Encrypted Files)                        │  ║
 ║  │  • Portfolio transactions                                               │  ║
 ║  │  • Connected exchange accounts                                          │  ║
 ║  │  • Wallet addresses (not keys)                                          │  ║
 ║  │  • Chat history (may contain financial info)                            │  ║
 ║  │  • AES-256-GCM encryption                                               │  ║
 ║  │  • iOS File Protection enabled                                          │  ║
 ║  └─────────────────────────────────────────────────────────────────────────┘  ║
 ║                                    ▲                                          ║
 ║                                    │                                          ║
 ║  ┌─────────────────────────────────────────────────────────────────────────┐  ║
 ║  │                        PUBLIC (UserDefaults)                            │  ║
 ║  │  • UI preferences (dark mode, etc.)                                     │  ║
 ║  │  • Feature flags                                                        │  ║
 ║  │  • Non-sensitive app settings                                           │  ║
 ║  │  • Last viewed screens                                                  │  ║
 ║  └─────────────────────────────────────────────────────────────────────────┘  ║
 ║                                                                               ║
 ║  KEY PRINCIPLES:                                                              ║
 ║  1. All sensitive data encrypted at rest                                     ║
 ║  2. API keys NEVER leave the device                                          ║
 ║  3. No sensitive data in UserDefaults                                        ║
 ║  4. Memory cleared on background                                             ║
 ║  5. Device-specific encryption keys                                          ║
 ║                                                                               ║
 ╚═══════════════════════════════════════════════════════════════════════════════╝
 
*/
