//
//  HardwareWalletProtocol.swift
//  CryptoSage
//
//  Protocol definitions and models for hardware wallet integration
//  (Ledger, Trezor).
//

import Foundation
import SwiftUI
import Combine

// MARK: - Hardware Wallet Provider Protocol

/// Protocol that all hardware wallet providers must implement
public protocol HardwareWalletProvider: ObservableObject {
    /// Unique identifier for this provider
    var id: String { get }
    
    /// Display name
    var name: String { get }
    
    /// Supported blockchain networks
    var supportedChains: [Chain] { get }
    
    /// Current connection state
    var connectionState: HWConnectionState { get }
    
    /// Whether the wallet is currently connected
    var isConnected: Bool { get }
    
    /// Last error that occurred
    var lastError: HardwareWalletError? { get }
    
    /// Connect to the hardware wallet
    func connect() async throws
    
    /// Disconnect from the hardware wallet
    func disconnect() async
    
    /// Get accounts/addresses for a specific chain
    func getAccounts(for chain: Chain) async throws -> [HWAccount]
    
    /// Sign a message with a specific account
    func signMessage(_ message: Data, account: HWAccount) async throws -> Data
    
    /// Sign a typed data message (EIP-712)
    func signTypedData(_ typedData: HWTypedData, account: HWAccount) async throws -> Data
    
    /// Sign a transaction
    func signTransaction(_ transaction: HWTransaction, account: HWAccount) async throws -> Data
}

// MARK: - Connection State

public enum HWConnectionState: String, Codable, Equatable {
    case disconnected
    case scanning
    case connecting
    case connected
    case appNotOpen
    case error
    
    public var displayName: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .scanning: return "Scanning..."
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .appNotOpen: return "Open App on Device"
        case .error: return "Error"
        }
    }
    
    public var icon: String {
        switch self {
        case .disconnected: return "xmark.circle"
        case .scanning: return "antenna.radiowaves.left.and.right"
        case .connecting: return "link"
        case .connected: return "checkmark.circle.fill"
        case .appNotOpen: return "exclamationmark.triangle"
        case .error: return "exclamationmark.circle"
        }
    }
    
    public var color: Color {
        switch self {
        case .disconnected: return .gray
        case .scanning, .connecting: return .blue
        case .connected: return .green
        case .appNotOpen: return .orange
        case .error: return .red
        }
    }
}

// MARK: - Hardware Wallet Account

/// Represents an account/address from a hardware wallet
public struct HWAccount: Identifiable, Codable, Equatable, Hashable {
    public let id: String
    public let address: String
    public let chain: Chain
    public let derivationPath: String
    public let publicKey: String?
    public let name: String?
    public let index: Int
    public let walletType: HWWalletType
    
    public init(
        id: String? = nil,
        address: String,
        chain: Chain,
        derivationPath: String,
        publicKey: String? = nil,
        name: String? = nil,
        index: Int = 0,
        walletType: HWWalletType
    ) {
        self.id = id ?? "\(walletType.rawValue):\(chain.rawValue):\(address)"
        self.address = address
        self.chain = chain
        self.derivationPath = derivationPath
        self.publicKey = publicKey
        self.name = name
        self.index = index
        self.walletType = walletType
    }
    
    /// Shortened address for display
    public var shortAddress: String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }
    
    /// Display name with fallback
    public var displayName: String {
        name ?? "Account \(index + 1)"
    }
}

// MARK: - Hardware Wallet Type

public enum HWWalletType: String, Codable, CaseIterable {
    case ledger = "ledger"
    case trezor = "trezor"
    
    public var displayName: String {
        switch self {
        case .ledger: return "Ledger"
        case .trezor: return "Trezor"
        }
    }
    
    public var iconName: String {
        switch self {
        case .ledger: return "shield.checkered"
        case .trezor: return "lock.shield"
        }
    }
    
    public var supportedModels: [String] {
        switch self {
        case .ledger: return ["Nano X", "Nano S Plus", "Stax"]
        case .trezor: return ["Model T", "Model One", "Safe 3"]
        }
    }
    
    public var connectionMethod: HWConnectionMethod {
        switch self {
        case .ledger: return .bluetooth
        case .trezor: return .bridge
        }
    }
}

public enum HWConnectionMethod: String, Codable {
    case bluetooth
    case usb
    case bridge
    
    public var displayName: String {
        switch self {
        case .bluetooth: return "Bluetooth"
        case .usb: return "USB"
        case .bridge: return "Trezor Bridge"
        }
    }
}

// MARK: - Hardware Wallet Transaction

/// Transaction data for hardware wallet signing
public struct HWTransaction: Codable, Equatable {
    public let chain: Chain
    public let from: String
    public let to: String
    public let value: String // Wei/smallest unit as hex string
    public let data: String? // Contract data
    public let nonce: String? // Hex
    public let gasLimit: String? // Hex
    public let gasPrice: String? // Hex (legacy)
    public let maxFeePerGas: String? // Hex (EIP-1559)
    public let maxPriorityFeePerGas: String? // Hex (EIP-1559)
    public let chainId: Int
    
    public init(
        chain: Chain,
        from: String,
        to: String,
        value: String,
        data: String? = nil,
        nonce: String? = nil,
        gasLimit: String? = nil,
        gasPrice: String? = nil,
        maxFeePerGas: String? = nil,
        maxPriorityFeePerGas: String? = nil,
        chainId: Int? = nil
    ) {
        self.chain = chain
        self.from = from
        self.to = to
        self.value = value
        self.data = data
        self.nonce = nonce
        self.gasLimit = gasLimit
        self.gasPrice = gasPrice
        self.maxFeePerGas = maxFeePerGas
        self.maxPriorityFeePerGas = maxPriorityFeePerGas
        self.chainId = chainId ?? chain.chainId ?? 1
    }
    
    /// Whether this is an EIP-1559 transaction
    public var isEIP1559: Bool {
        maxFeePerGas != nil && maxPriorityFeePerGas != nil
    }
}

// MARK: - EIP-712 Typed Data

/// Typed data structure for EIP-712 signing
public struct HWTypedData: Codable, Equatable {
    public let types: [String: [HWTypedDataField]]
    public let primaryType: String
    public let domain: HWTypedDataDomain
    public let message: [String: Any]
    
    public init(
        types: [String: [HWTypedDataField]],
        primaryType: String,
        domain: HWTypedDataDomain,
        message: [String: Any]
    ) {
        self.types = types
        self.primaryType = primaryType
        self.domain = domain
        self.message = message
    }
    
    // Custom Codable implementation for message dictionary
    enum CodingKeys: String, CodingKey {
        case types, primaryType, domain, message
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        types = try container.decode([String: [HWTypedDataField]].self, forKey: .types)
        primaryType = try container.decode(String.self, forKey: .primaryType)
        domain = try container.decode(HWTypedDataDomain.self, forKey: .domain)
        
        // Decode message as a generic dictionary
        let messageContainer = try container.decode([String: AnyCodable].self, forKey: .message)
        message = messageContainer.mapValues { $0.value }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(types, forKey: .types)
        try container.encode(primaryType, forKey: .primaryType)
        try container.encode(domain, forKey: .domain)
        
        let messageContainer = message.mapValues { AnyCodable($0) }
        try container.encode(messageContainer, forKey: .message)
    }
    
    public static func == (lhs: HWTypedData, rhs: HWTypedData) -> Bool {
        lhs.primaryType == rhs.primaryType &&
        lhs.domain == rhs.domain &&
        lhs.types == rhs.types
    }
}

public struct HWTypedDataField: Codable, Equatable {
    public let name: String
    public let type: String
    
    public init(name: String, type: String) {
        self.name = name
        self.type = type
    }
}

public struct HWTypedDataDomain: Codable, Equatable {
    public let name: String?
    public let version: String?
    public let chainId: Int?
    public let verifyingContract: String?
    public let salt: String?
    
    public init(
        name: String? = nil,
        version: String? = nil,
        chainId: Int? = nil,
        verifyingContract: String? = nil,
        salt: String? = nil
    ) {
        self.name = name
        self.version = version
        self.chainId = chainId
        self.verifyingContract = verifyingContract
        self.salt = salt
    }
}

// MARK: - Derivation Paths

/// Common derivation paths for different chains
public enum HWDerivationPath {
    /// BIP44 standard paths
    public static func bip44(coin: Int, account: Int = 0, change: Int = 0, index: Int = 0) -> String {
        "m/44'/\(coin)'/\(account)'/\(change)/\(index)"
    }
    
    /// Ethereum (and EVM chains)
    public static func ethereum(account: Int = 0, index: Int = 0) -> String {
        bip44(coin: 60, account: account, index: index)
    }
    
    /// Ethereum Ledger Live path
    public static func ethereumLedgerLive(account: Int = 0) -> String {
        "m/44'/60'/\(account)'/0/0"
    }
    
    /// Bitcoin
    public static func bitcoin(account: Int = 0, change: Int = 0, index: Int = 0) -> String {
        bip44(coin: 0, account: account, change: change, index: index)
    }
    
    /// Bitcoin SegWit (BIP84)
    public static func bitcoinSegWit(account: Int = 0, change: Int = 0, index: Int = 0) -> String {
        "m/84'/0'/\(account)'/\(change)/\(index)"
    }
    
    /// Solana
    public static func solana(account: Int = 0) -> String {
        "m/44'/501'/\(account)'/0'"
    }
    
    /// Get default path for a chain
    public static func defaultPath(for chain: Chain, index: Int = 0) -> String {
        switch chain {
        case .bitcoin:
            return bitcoinSegWit(index: index)
        case .solana:
            return solana(account: index)
        default:
            // EVM chains use Ethereum path
            return ethereum(index: index)
        }
    }
}

// MARK: - Hardware Wallet Errors

public enum HardwareWalletError: LocalizedError {
    case notConnected
    case connectionFailed(String)
    case deviceNotFound
    case userCancelled
    case appNotOpen(String) // Chain app name
    case signingFailed(String)
    case invalidTransaction
    case invalidMessage
    case unsupportedChain(Chain)
    case unsupportedOperation
    case communicationError(String)
    case timeout
    case bluetoothDisabled
    case bluetoothUnauthorized
    case bridgeNotRunning
    case unknown(String)
    
    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Hardware wallet is not connected"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .deviceNotFound:
            return "Hardware wallet not found. Make sure it's turned on and nearby."
        case .userCancelled:
            return "Operation cancelled by user"
        case .appNotOpen(let app):
            return "Please open the \(app) app on your hardware wallet"
        case .signingFailed(let reason):
            return "Signing failed: \(reason)"
        case .invalidTransaction:
            return "Invalid transaction data"
        case .invalidMessage:
            return "Invalid message data"
        case .unsupportedChain(let chain):
            return "\(chain.displayName) is not supported by this hardware wallet"
        case .unsupportedOperation:
            return "This operation is not supported"
        case .communicationError(let reason):
            return "Communication error: \(reason)"
        case .timeout:
            return "Operation timed out"
        case .bluetoothDisabled:
            return "Bluetooth is disabled. Please enable it in Settings."
        case .bluetoothUnauthorized:
            return "Bluetooth access denied. Please allow access in Settings."
        case .bridgeNotRunning:
            return "Trezor Bridge is not running. Please install and run Trezor Suite."
        case .unknown(let reason):
            return reason
        }
    }
}

// MARK: - Discovered Device

/// Represents a discovered hardware wallet device
public struct HWDiscoveredDevice: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let type: HWWalletType
    public let model: String?
    public let connectionMethod: HWConnectionMethod
    public var rssi: Int? // Bluetooth signal strength
    
    public init(
        id: String,
        name: String,
        type: HWWalletType,
        model: String? = nil,
        connectionMethod: HWConnectionMethod,
        rssi: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.model = model
        self.connectionMethod = connectionMethod
        self.rssi = rssi
    }
    
    public var displayName: String {
        if let model = model {
            return "\(type.displayName) \(model)"
        }
        return name
    }
}

// MARK: - Signing Request

/// Represents a pending signing request
public struct HWSigningRequest: Identifiable {
    public let id: UUID
    public let account: HWAccount
    public let requestType: HWSigningRequestType
    public let displayInfo: HWSigningDisplayInfo
    public let createdAt: Date
    
    public init(
        id: UUID = UUID(),
        account: HWAccount,
        requestType: HWSigningRequestType,
        displayInfo: HWSigningDisplayInfo,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.account = account
        self.requestType = requestType
        self.displayInfo = displayInfo
        self.createdAt = createdAt
    }
}

public enum HWSigningRequestType {
    case message(Data)
    case typedData(HWTypedData)
    case transaction(HWTransaction)
}

public struct HWSigningDisplayInfo {
    public let title: String
    public let subtitle: String?
    public let details: [(label: String, value: String)]
    public let warningMessage: String?
    
    public init(
        title: String,
        subtitle: String? = nil,
        details: [(label: String, value: String)] = [],
        warningMessage: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.details = details
        self.warningMessage = warningMessage
    }
}
