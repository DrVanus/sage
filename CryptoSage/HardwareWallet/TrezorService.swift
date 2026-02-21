//
//  TrezorService.swift
//  CryptoSage
//
//  Trezor hardware wallet integration via Trezor Suite deep linking.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Trezor Service

public final class TrezorService: NSObject, HardwareWalletProvider, ObservableObject {
    public var id: String { "trezor" }
    public var name: String { "Trezor" }
    public var supportedChains: [Chain] {
        [.ethereum, .bitcoin, .polygon]
    }
    
    // MARK: - Published Properties
    
    @Published public var connectionState: HWConnectionState = .disconnected
    @Published public var isConnected: Bool = false
    @Published public var lastError: HardwareWalletError?
    @Published public var connectedDevice: HWDiscoveredDevice?
    @Published public var pendingAction: TrezorAction?
    
    // MARK: - Private Properties
    
    private var importedAccounts: [HWAccount] = []
    private let bridgeURL = URL(string: "http://127.0.0.1:21325")!
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    public override init() {
        super.init()
        loadImportedAccounts()
    }
    
    // MARK: - HardwareWalletProvider Protocol
    
    public func connect() async throws {
        await MainActor.run {
            connectionState = .connecting
        }
        
        // Check if Trezor Bridge is running
        let bridgeAvailable = await checkBridgeAvailability()
        
        if bridgeAvailable {
            // Use Trezor Bridge
            try await connectViaBridge()
        } else {
            // Fallback to Trezor Suite deep linking
            await MainActor.run {
                connectionState = .appNotOpen
                lastError = .bridgeNotRunning
            }
            throw HardwareWalletError.bridgeNotRunning
        }
    }
    
    public func disconnect() async {
        await MainActor.run {
            connectionState = .disconnected
            isConnected = false
            connectedDevice = nil
        }
    }
    
    public func getAccounts(for chain: Chain) async throws -> [HWAccount] {
        guard isConnected || !importedAccounts.isEmpty else {
            throw HardwareWalletError.notConnected
        }
        
        // Return cached accounts for the chain
        let chainAccounts = importedAccounts.filter { $0.chain == chain }
        if !chainAccounts.isEmpty {
            return chainAccounts
        }
        
        // Otherwise, request via deep link
        return try await requestAccounts(for: chain)
    }
    
    public func signMessage(_ message: Data, account: HWAccount) async throws -> Data {
        guard isConnected else {
            throw HardwareWalletError.notConnected
        }
        
        return try await signViaTrezorSuite(
            action: .signMessage(message: message, path: account.derivationPath, chain: account.chain)
        )
    }
    
    public func signTypedData(_ typedData: HWTypedData, account: HWAccount) async throws -> Data {
        guard isConnected else {
            throw HardwareWalletError.notConnected
        }
        
        return try await signViaTrezorSuite(
            action: .signTypedData(data: typedData, path: account.derivationPath)
        )
    }
    
    public func signTransaction(_ transaction: HWTransaction, account: HWAccount) async throws -> Data {
        guard isConnected else {
            throw HardwareWalletError.notConnected
        }
        
        return try await signViaTrezorSuite(
            action: .signTransaction(tx: transaction, path: account.derivationPath)
        )
    }
    
    // MARK: - Public Methods
    
    /// Open Trezor Suite for a specific action
    public func openTrezorSuite(for action: TrezorAction) -> URL? {
        var components = URLComponents()
        components.scheme = "trezorsuite"
        
        switch action {
        case .connect:
            components.host = "connect"
        case .getAddress(let path, let chain):
            components.host = "get-address"
            components.queryItems = [
                URLQueryItem(name: "path", value: path),
                URLQueryItem(name: "coin", value: chain.trezorCoinName)
            ]
        case .signMessage(let message, let path, let chain):
            components.host = "sign-message"
            components.queryItems = [
                URLQueryItem(name: "message", value: message.base64EncodedString()),
                URLQueryItem(name: "path", value: path),
                URLQueryItem(name: "coin", value: chain.trezorCoinName)
            ]
        case .signTypedData(_, let path):
            components.host = "sign-typed-data"
            components.queryItems = [
                URLQueryItem(name: "path", value: path)
            ]
        case .signTransaction(let tx, let path):
            components.host = "sign-transaction"
            components.queryItems = [
                URLQueryItem(name: "path", value: path),
                URLQueryItem(name: "to", value: tx.to),
                URLQueryItem(name: "value", value: tx.value),
                URLQueryItem(name: "chainId", value: String(tx.chainId))
            ]
        }
        
        return components.url
    }
    
    /// Import an account manually (for when using deep linking)
    public func importAccount(address: String, chain: Chain, path: String, index: Int = 0) {
        let account = HWAccount(
            address: address,
            chain: chain,
            derivationPath: path,
            index: index,
            walletType: .trezor
        )
        
        if !importedAccounts.contains(where: { $0.id == account.id }) {
            importedAccounts.append(account)
            saveImportedAccounts()
        }
        
        Task { @MainActor in
            isConnected = true
            connectionState = .connected
        }
    }
    
    /// Remove an imported account
    public func removeAccount(_ account: HWAccount) {
        importedAccounts.removeAll { $0.id == account.id }
        saveImportedAccounts()
    }
    
    // MARK: - Private Methods
    
    private func checkBridgeAvailability() async -> Bool {
        let url = bridgeURL.appendingPathComponent("status")
        
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
        } catch {
            return false
        }
        
        return false
    }
    
    private func connectViaBridge() async throws {
        // Enumerate devices
        let url = bridgeURL.appendingPathComponent("enumerate")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw HardwareWalletError.connectionFailed("Bridge returned error")
        }
        
        let devices = try JSONDecoder().decode([TrezorBridgeDevice].self, from: data)
        
        guard let device = devices.first else {
            throw HardwareWalletError.deviceNotFound
        }
        
        // Acquire session
        let acquireURL = bridgeURL.appendingPathComponent("acquire/\(device.path)/null")
        var acquireRequest = URLRequest(url: acquireURL)
        acquireRequest.httpMethod = "POST"
        
        let (sessionData, _) = try await URLSession.shared.data(for: acquireRequest)
        _ = try JSONDecoder().decode(TrezorBridgeSession.self, from: sessionData)
        
        await MainActor.run {
            connectionState = .connected
            isConnected = true
            connectedDevice = HWDiscoveredDevice(
                id: device.path,
                name: "Trezor",
                type: .trezor,
                model: detectModel(from: device),
                connectionMethod: .bridge
            )
        }
    }
    
    private func requestAccounts(for chain: Chain) async throws -> [HWAccount] {
        let accounts: [HWAccount] = []
        
        for index in 0..<5 {
            let path = HWDerivationPath.defaultPath(for: chain, index: index)
            
            if let url = openTrezorSuite(for: .getAddress(path: path, chain: chain)) {
                await MainActor.run {
                    pendingAction = .getAddress(path: path, chain: chain)
                    #if os(iOS)
                    UIApplication.shared.open(url)
                    #endif
                }
                
                // Wait for callback (in real app, would use URL scheme callback)
                try await Task.sleep(nanoseconds: 500_000_000)
            }
        }
        
        return accounts
    }
    
    private func signViaTrezorSuite(action: TrezorAction) async throws -> Data {
        guard let url = openTrezorSuite(for: action) else {
            throw HardwareWalletError.invalidMessage
        }
        
        await MainActor.run {
            pendingAction = action
            #if os(iOS)
            UIApplication.shared.open(url)
            #endif
        }
        
        // In real implementation, would wait for callback with signature
        throw HardwareWalletError.unsupportedOperation
    }
    
    private func detectModel(from device: TrezorBridgeDevice) -> String? {
        // Model detection based on device info
        return "Model T"
    }
    
    private func loadImportedAccounts() {
        guard let data = UserDefaults.standard.data(forKey: "trezor_accounts"),
              let accounts = try? JSONDecoder().decode([HWAccount].self, from: data) else {
            return
        }
        importedAccounts = accounts
        
        if !accounts.isEmpty {
            Task { @MainActor in
                isConnected = true
                connectionState = .connected
            }
        }
    }
    
    private func saveImportedAccounts() {
        guard let data = try? JSONEncoder().encode(importedAccounts) else { return }
        UserDefaults.standard.set(data, forKey: "trezor_accounts")
    }
}

// MARK: - Trezor Action

public enum TrezorAction: Equatable {
    case connect
    case getAddress(path: String, chain: Chain)
    case signMessage(message: Data, path: String, chain: Chain)
    case signTypedData(data: HWTypedData, path: String)
    case signTransaction(tx: HWTransaction, path: String)
}

// MARK: - Trezor Bridge Models

private struct TrezorBridgeDevice: Codable {
    let path: String
    let vendor: Int?
    let product: Int?
    let session: String?
}

private struct TrezorBridgeSession: Codable {
    let session: String
}

// MARK: - Chain Extension

extension Chain {
    var trezorCoinName: String {
        switch self {
        case .bitcoin: return "btc"
        case .ethereum: return "eth"
        case .polygon: return "matic"
        default: return "eth"
        }
    }
}
