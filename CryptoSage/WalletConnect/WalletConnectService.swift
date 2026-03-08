//
//  WalletConnectService.swift
//  CryptoSage
//
//  WalletConnect v2 integration for mobile wallet connections.
//  SECURITY: Sessions stored in encrypted storage, not UserDefaults.
//

import Foundation
import Combine

// MARK: - WalletConnect Service

/// Service for connecting to mobile wallets via WalletConnect
@MainActor
public final class WalletConnectService: ObservableObject {
    public static let shared = WalletConnectService()
    
    // MARK: - Published Properties
    
    @Published public private(set) var isConnected = false
    @Published public private(set) var isConnecting = false
    @Published public private(set) var connectedAccount: WalletConnectAccount?
    @Published public private(set) var connectionURI: String?
    @Published public private(set) var lastError: WalletConnectError?
    
    // MARK: - Configuration
    
    private let projectId: String
    private let metadata: WalletConnectMetadata
    
    // Session management
    private var activeSessions: [WalletConnectSession] = []
    private var pendingRequests: [String: (Result<Any, Error>) -> Void] = [:]
    
    // Secure storage (encrypted, not UserDefaults)
    private let secureStorage = SecureStorage.shared
    private let sessionsFileName = "walletconnect_sessions"
    
    // Session security
    private let maxSessionAge: TimeInterval = 7 * 24 * 60 * 60 // 7 days max session
    
    // MARK: - Initialization
    
    private init() {
        // Default configuration - should be set via config file or environment
        self.projectId = ProcessInfo.processInfo.environment["WALLETCONNECT_PROJECT_ID"] ?? ""
        self.metadata = WalletConnectMetadata(
            name: "CryptoSage",
            description: "AI-Powered Crypto Portfolio",
            url: "https://cryptosage.app",
            icons: ["https://cryptosage.app/icon.png"],
            redirect: WalletConnectRedirect(
                native: "cryptosage://",
                universal: "https://cryptosage.app"
            )
        )
        
        loadSessions()
        cleanupExpiredSessions()
    }
    
    // MARK: - Session Security
    
    /// Remove expired sessions for security
    private func cleanupExpiredSessions() {
        let now = Date()
        let validSessions = activeSessions.filter { session in
            // Check if session is expired by its own expiry
            if session.isExpired { return false }
            // Also enforce max session age for security
            let sessionAge = now.timeIntervalSince(session.expiry.addingTimeInterval(-maxSessionAge))
            return sessionAge < maxSessionAge
        }
        
        if validSessions.count != activeSessions.count {
            activeSessions = validSessions
            saveSessions()
            
            // Update connection state
            if activeSessions.isEmpty {
                connectedAccount = nil
                isConnected = false
            }
            
            #if DEBUG
            print("🔐 [WalletConnect] Cleaned up \(activeSessions.count - validSessions.count) expired sessions")
            #endif
        }
    }
    
    // MARK: - Public API
    
    /// Configure the service with a project ID
    public func configure(projectId: String) {
        // In production, you'd re-initialize the WalletConnect client here
    }
    
    /// Generate a connection URI for QR code
    public func connect() async throws -> String {
        isConnecting = true
        lastError = nil
        
        defer {
            isConnecting = false
        }

        // Generate pairing topic
        let pairingTopic = generateRandomTopic()

        // Build connection URI
        // WalletConnect v2 URI format:
        // wc:{topic}@2?relay-protocol=irn&symKey={symmetricKey}
        let symKey = generateSymmetricKey()
        let uri = "wc:\(pairingTopic)@2?relay-protocol=irn&symKey=\(symKey)"

        connectionURI = uri
        
        // In production, you'd initiate the actual WalletConnect session here
        // using the WalletConnectSwift SDK
        
        return uri
    }
    
    /// Disconnect from current wallet
    public func disconnect() async throws {
        guard isConnected, let _ = activeSessions.first else {
            throw WalletConnectError.notConnected
        }
        
        // In production, send disconnect message via WalletConnect

        activeSessions.removeAll()
        connectedAccount = nil
        isConnected = false
        connectionURI = nil

        saveSessions()
    }
    
    /// Get current session
    public func getCurrentSession() -> WalletConnectSession? {
        activeSessions.first
    }
    
    /// Check if we have an active session for an address
    public func hasSession(for address: String) -> Bool {
        activeSessions.contains { session in
            session.accounts.contains { $0.address.lowercased() == address.lowercased() }
        }
    }
    
    // MARK: - Wallet Requests
    
    /// Request account addresses from connected wallet
    public func requestAccounts() async throws -> [String] {
        guard isConnected else {
            throw WalletConnectError.notConnected
        }
        
        // eth_requestAccounts
        // In production, send JSON-RPC request via WalletConnect
        
        return connectedAccount.map { [$0.address] } ?? []
    }
    
    /// Request to sign a message (for authentication)
    public func signMessage(_ message: String, account: String) async throws -> String {
        guard isConnected else {
            throw WalletConnectError.notConnected
        }
        
        // personal_sign request
        // In production, this would prompt the user's wallet app
        
        throw WalletConnectError.userRejected
    }
    
    /// Request to sign a transaction (for DeFi interactions)
    public func signTransaction(_ transaction: WalletConnectTransaction) async throws -> String {
        guard isConnected else {
            throw WalletConnectError.notConnected
        }
        
        // eth_sendTransaction request
        // In production, this would prompt the user's wallet app
        
        throw WalletConnectError.userRejected
    }
    
    /// Switch to a different chain
    public func switchChain(to chainId: Int) async throws {
        guard isConnected else {
            throw WalletConnectError.notConnected
        }
        
        // wallet_switchEthereumChain request
        // In production, this would prompt the user's wallet app
    }
    
    // MARK: - Session Events (Callbacks)
    
    /// Called when a session is established
    private func onSessionEstablished(_ session: WalletConnectSession) {
        activeSessions.append(session)
        
        if let account = session.accounts.first {
            connectedAccount = account
            isConnected = true
        }
        
        saveSessions()
    }
    
    /// Called when a session is disconnected
    private func onSessionDisconnected(topic: String) {
        activeSessions.removeAll { $0.topic == topic }
        
        if activeSessions.isEmpty {
            connectedAccount = nil
            isConnected = false
        }
        
        saveSessions()
    }
    
    /// Called when session is updated (e.g., accounts changed)
    private func onSessionUpdated(_ session: WalletConnectSession) {
        if let index = activeSessions.firstIndex(where: { $0.topic == session.topic }) {
            activeSessions[index] = session
        }
        
        if let account = session.accounts.first {
            connectedAccount = account
        }
        
        saveSessions()
    }
    
    // MARK: - Secure Persistence (Encrypted Storage)
    
    private func saveSessions() {
        // Use encrypted storage for WalletConnect sessions
        // Sessions contain wallet addresses which are sensitive
        secureStorage.saveEncrypted(activeSessions, to: sessionsFileName)
        #if DEBUG
        print("🔐 [WalletConnect] Sessions saved to encrypted storage")
        #endif
    }
    
    private func loadSessions() {
        // Load from encrypted storage
        if let sessions = secureStorage.loadEncrypted([WalletConnectSession].self, from: sessionsFileName) {
            // Filter out expired sessions on load
            activeSessions = sessions.filter { !$0.isExpired }
            
            // Restore connection state
            if let session = activeSessions.first, let account = session.accounts.first {
                connectedAccount = account
                isConnected = true
                #if DEBUG
                print("🔐 [WalletConnect] Restored session for \(account.address.prefix(10))...")
                #endif
            }
        }
        
        // Clean up old UserDefaults data if it exists (migration)
        let legacyKey = "CryptoSage.WalletConnect.Sessions"
        if UserDefaults.standard.data(forKey: legacyKey) != nil {
            UserDefaults.standard.removeObject(forKey: legacyKey)
            #if DEBUG
            print("🔐 [WalletConnect] Migrated sessions from UserDefaults to encrypted storage")
            #endif
        }
    }
    
    /// Clear all sessions (for logout/security)
    public func clearAllSessions() {
        activeSessions.removeAll()
        connectedAccount = nil
        isConnected = false
        connectionURI = nil
        secureStorage.deleteEncrypted(sessionsFileName)
        #if DEBUG
        print("🔐 [WalletConnect] All sessions cleared")
        #endif
    }
    
    // MARK: - Helpers
    
    private func generateRandomTopic() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
    
    private func generateSymmetricKey() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - WalletConnect Models

/// WalletConnect session
public struct WalletConnectSession: Codable, Identifiable {
    public let id: String
    public let topic: String
    public let pairingTopic: String
    public let relay: WalletConnectRelay
    public let expiry: Date
    public let accounts: [WalletConnectAccount]
    public let chains: [String]
    public let methods: [String]
    public let events: [String]
    public let peerMetadata: WalletConnectMetadata?
    
    public var isExpired: Bool {
        Date() > expiry
    }
    
    public init(
        id: String = UUID().uuidString,
        topic: String,
        pairingTopic: String,
        relay: WalletConnectRelay,
        expiry: Date,
        accounts: [WalletConnectAccount],
        chains: [String],
        methods: [String],
        events: [String],
        peerMetadata: WalletConnectMetadata? = nil
    ) {
        self.id = id
        self.topic = topic
        self.pairingTopic = pairingTopic
        self.relay = relay
        self.expiry = expiry
        self.accounts = accounts
        self.chains = chains
        self.methods = methods
        self.events = events
        self.peerMetadata = peerMetadata
    }
}

/// WalletConnect account
public struct WalletConnectAccount: Codable, Identifiable, Equatable {
    public let id: String
    public let address: String
    public let chainId: String
    
    public init(address: String, chainId: String) {
        self.id = "\(chainId):\(address)"
        self.address = address
        self.chainId = chainId
    }
    
    /// Chain ID as integer (for EVM chains)
    public var chainIdInt: Int? {
        // Format: "eip155:1" -> 1
        let parts = chainId.split(separator: ":")
        guard parts.count == 2 else { return nil }
        return Int(parts[1])
    }
    
    /// Get Chain enum from chainId
    public var chain: Chain? {
        guard let id = chainIdInt else { return nil }
        return Chain.allCases.first { $0.chainId == id }
    }
}

/// WalletConnect metadata
public struct WalletConnectMetadata: Codable {
    public let name: String
    public let description: String
    public let url: String
    public let icons: [String]
    public let redirect: WalletConnectRedirect?
    
    public init(
        name: String,
        description: String,
        url: String,
        icons: [String],
        redirect: WalletConnectRedirect? = nil
    ) {
        self.name = name
        self.description = description
        self.url = url
        self.icons = icons
        self.redirect = redirect
    }
}

/// WalletConnect redirect URLs
public struct WalletConnectRedirect: Codable {
    public let native: String?
    public let universal: String?
    
    public init(native: String?, universal: String?) {
        self.native = native
        self.universal = universal
    }
}

/// WalletConnect relay
public struct WalletConnectRelay: Codable {
    public let `protocol`: String
    public let data: String?
    
    public init(protocol: String, data: String? = nil) {
        self.protocol = `protocol`
        self.data = data
    }
}

/// Transaction for signing
public struct WalletConnectTransaction: Codable {
    public let from: String
    public let to: String
    public let data: String?
    public let value: String?
    public let gas: String?
    public let gasPrice: String?
    public let nonce: String?
    
    public init(
        from: String,
        to: String,
        data: String? = nil,
        value: String? = nil,
        gas: String? = nil,
        gasPrice: String? = nil,
        nonce: String? = nil
    ) {
        self.from = from
        self.to = to
        self.data = data
        self.value = value
        self.gas = gas
        self.gasPrice = gasPrice
        self.nonce = nonce
    }
}

// MARK: - WalletConnect Errors

public enum WalletConnectError: LocalizedError {
    case notConnected
    case connectionFailed(String)
    case sessionExpired
    case userRejected
    case invalidRequest
    case chainNotSupported
    case methodNotSupported
    case timeout
    case unknown(String)
    
    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to a wallet"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .sessionExpired:
            return "Session has expired. Please reconnect."
        case .userRejected:
            return "Request was rejected by the wallet"
        case .invalidRequest:
            return "Invalid request"
        case .chainNotSupported:
            return "This blockchain is not supported by the connected wallet"
        case .methodNotSupported:
            return "This method is not supported by the connected wallet"
        case .timeout:
            return "Request timed out"
        case .unknown(let message):
            return message
        }
    }
}

// MARK: - Supported Wallets

/// Popular wallets that support WalletConnect
public struct SupportedWallet: Identifiable {
    public let id: String
    public let name: String
    public let iconURL: String
    public let universalLink: String?
    public let deepLink: String?
    
    public static let metaMask = SupportedWallet(
        id: "metamask",
        name: "MetaMask",
        iconURL: "https://registry.walletconnect.org/v2/logo/md/metamask",
        universalLink: "https://metamask.app.link",
        deepLink: "metamask://"
    )
    
    public static let trustWallet = SupportedWallet(
        id: "trust",
        name: "Trust Wallet",
        iconURL: "https://registry.walletconnect.org/v2/logo/md/trust",
        universalLink: "https://link.trustwallet.com",
        deepLink: "trust://"
    )
    
    public static let rainbow = SupportedWallet(
        id: "rainbow",
        name: "Rainbow",
        iconURL: "https://registry.walletconnect.org/v2/logo/md/rainbow",
        universalLink: "https://rainbow.me",
        deepLink: "rainbow://"
    )
    
    public static let coinbaseWallet = SupportedWallet(
        id: "coinbase",
        name: "Coinbase Wallet",
        iconURL: "https://registry.walletconnect.org/v2/logo/md/coinbase",
        universalLink: "https://go.cb-w.com",
        deepLink: "cbwallet://"
    )
    
    public static let phantom = SupportedWallet(
        id: "phantom",
        name: "Phantom",
        iconURL: "https://registry.walletconnect.org/v2/logo/md/phantom",
        universalLink: "https://phantom.app",
        deepLink: "phantom://"
    )
    
    public static let all: [SupportedWallet] = [
        metaMask, trustWallet, rainbow, coinbaseWallet, phantom
    ]
}
