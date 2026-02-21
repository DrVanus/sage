//
//  LedgerService.swift
//  CryptoSage
//
//  Ledger hardware wallet integration via Bluetooth Low Energy (BLE).
//  Supports Ledger Nano X and other Bluetooth-enabled devices.
//

import Foundation
import CoreBluetooth
import Combine

// MARK: - Ledger Service

public final class LedgerService: NSObject, HardwareWalletProvider, ObservableObject {
    public var id: String { "ledger" }
    public var name: String { "Ledger" }
    public var supportedChains: [Chain] {
        [.ethereum, .bitcoin, .polygon, .arbitrum, .optimism, .bsc, .avalanche, .base]
    }
    
    // MARK: - Published Properties
    
    @Published public var connectionState: HWConnectionState = .disconnected
    @Published public var isConnected: Bool = false
    @Published public var lastError: HardwareWalletError?
    @Published public var discoveredDevices: [HWDiscoveredDevice] = []
    @Published public var connectedDevice: HWDiscoveredDevice?
    @Published public var currentApp: LedgerApp?
    @Published public var deviceInfo: LedgerDeviceInfo?
    
    // MARK: - Private Properties
    
    private var centralManager: CBCentralManager?
    private var connectedPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    
    private var pendingResponse: CheckedContinuation<Data, Error>?
    private var responseBuffer = Data()
    
    private let ledgerServiceUUID = CBUUID(string: "13D63400-2C97-0004-0000-4C6564676572")
    private let writeCharacteristicUUID = CBUUID(string: "13D63400-2C97-0004-0002-4C6564676572")
    private let notifyCharacteristicUUID = CBUUID(string: "13D63400-2C97-0004-0001-4C6564676572")
    
    private var scanTimeout: DispatchWorkItem?
    private var connectionTimeout: DispatchWorkItem?
    
    // MARK: - Initialization
    
    public override init() {
        super.init()
    }
    
    // MARK: - HardwareWalletProvider Protocol
    
    public func connect() async throws {
        guard connectionState != .connected else { return }
        
        // Initialize CoreBluetooth
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: .main)
        }
        
        // Wait for Bluetooth to be ready
        try await waitForBluetoothReady()
        
        // Start scanning
        await startScanning()
        
        // Wait for device discovery and connection
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // This will be completed when we successfully connect
            Task { @MainActor in
                // Set a timeout
                self.connectionTimeout?.cancel()
                self.connectionTimeout = DispatchWorkItem { [weak self] in
                    if self?.connectionState != .connected {
                        self?.connectionState = .error
                        self?.lastError = .timeout
                        continuation.resume(throwing: HardwareWalletError.timeout)
                    }
                }
                
                if let timeout = self.connectionTimeout {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: timeout)
                }
                
                // Monitor for connection
                var cancellable: AnyCancellable?
                cancellable = self.$connectionState
                    .dropFirst()
                    .sink { state in
                        if state == .connected {
                            self.connectionTimeout?.cancel()
                            cancellable?.cancel()
                            continuation.resume()
                        } else if state == .error {
                            self.connectionTimeout?.cancel()
                            cancellable?.cancel()
                            continuation.resume(throwing: self.lastError ?? HardwareWalletError.connectionFailed("Unknown error"))
                        }
                    }
            }
        }
    }
    
    public func disconnect() async {
        if let peripheral = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        
        await MainActor.run {
            connectionState = .disconnected
            isConnected = false
            connectedPeripheral = nil
            connectedDevice = nil
            writeCharacteristic = nil
            notifyCharacteristic = nil
            currentApp = nil
        }
    }
    
    public func getAccounts(for chain: Chain) async throws -> [HWAccount] {
        guard isConnected else {
            throw HardwareWalletError.notConnected
        }
        
        // Check if correct app is open
        let requiredApp = appName(for: chain)
        if currentApp?.name != requiredApp {
            throw HardwareWalletError.appNotOpen(requiredApp)
        }
        
        var accounts: [HWAccount] = []
        
        // Fetch first 5 accounts
        for index in 0..<5 {
            let path = HWDerivationPath.defaultPath(for: chain, index: index)
            
            do {
                let address = try await getAddress(derivationPath: path, chain: chain)
                let account = HWAccount(
                    address: address,
                    chain: chain,
                    derivationPath: path,
                    index: index,
                    walletType: .ledger
                )
                accounts.append(account)
            } catch {
                // Stop if we can't get more accounts
                break
            }
        }
        
        return accounts
    }
    
    public func signMessage(_ message: Data, account: HWAccount) async throws -> Data {
        guard isConnected else {
            throw HardwareWalletError.notConnected
        }
        
        // Check app
        let requiredApp = appName(for: account.chain)
        if currentApp?.name != requiredApp {
            throw HardwareWalletError.appNotOpen(requiredApp)
        }
        
        // Build APDU for personal_sign
        let apdu = buildSignMessageAPDU(message: message, path: account.derivationPath, chain: account.chain)
        
        let response = try await sendAPDU(apdu)
        
        // Parse signature from response
        guard response.count >= 65 else {
            throw HardwareWalletError.signingFailed("Invalid signature length")
        }
        
        return response
    }
    
    public func signTypedData(_ typedData: HWTypedData, account: HWAccount) async throws -> Data {
        guard isConnected else {
            throw HardwareWalletError.notConnected
        }
        
        // Ledger supports EIP-712 signing
        let requiredApp = appName(for: account.chain)
        if currentApp?.name != requiredApp {
            throw HardwareWalletError.appNotOpen(requiredApp)
        }
        
        // Build APDU for EIP-712 signing
        let apdu = buildSignTypedDataAPDU(typedData: typedData, path: account.derivationPath)
        
        let response = try await sendAPDU(apdu)
        
        guard response.count >= 65 else {
            throw HardwareWalletError.signingFailed("Invalid signature length")
        }
        
        return response
    }
    
    public func signTransaction(_ transaction: HWTransaction, account: HWAccount) async throws -> Data {
        guard isConnected else {
            throw HardwareWalletError.notConnected
        }
        
        let requiredApp = appName(for: account.chain)
        if currentApp?.name != requiredApp {
            throw HardwareWalletError.appNotOpen(requiredApp)
        }
        
        // Build APDU for transaction signing
        let apdu = buildSignTransactionAPDU(transaction: transaction, path: account.derivationPath)
        
        let response = try await sendAPDU(apdu)
        
        guard response.count >= 65 else {
            throw HardwareWalletError.signingFailed("Invalid signature length")
        }
        
        return response
    }
    
    // MARK: - Public Methods
    
    /// Start scanning for Ledger devices
    @MainActor
    public func startScanning() async {
        guard centralManager?.state == .poweredOn else {
            connectionState = .error
            lastError = .bluetoothDisabled
            return
        }
        
        connectionState = .scanning
        discoveredDevices = []
        
        centralManager?.scanForPeripherals(
            withServices: [ledgerServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        
        // Set scan timeout
        scanTimeout?.cancel()
        scanTimeout = DispatchWorkItem { [weak self] in
            self?.centralManager?.stopScan()
            if self?.discoveredDevices.isEmpty == true {
                Task { @MainActor in
                    self?.connectionState = .disconnected
                    self?.lastError = .deviceNotFound
                }
            }
        }
        
        if let timeout = scanTimeout {
            DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
        }
    }
    
    /// Stop scanning
    public func stopScanning() {
        scanTimeout?.cancel()
        centralManager?.stopScan()
        
        if connectionState == .scanning {
            Task { @MainActor in
                connectionState = .disconnected
            }
        }
    }
    
    /// Connect to a specific discovered device
    public func connect(to device: HWDiscoveredDevice) async throws {
        guard let peripheral = findPeripheral(for: device) else {
            throw HardwareWalletError.deviceNotFound
        }
        
        stopScanning()
        
        await MainActor.run {
            connectionState = .connecting
        }
        
        centralManager?.connect(peripheral, options: nil)
    }
    
    /// Get the app that needs to be open for a chain
    public func appName(for chain: Chain) -> String {
        switch chain {
        case .bitcoin:
            return "Bitcoin"
        case .ethereum, .polygon, .arbitrum, .optimism, .base, .bsc, .avalanche:
            return "Ethereum"
        case .solana:
            return "Solana"
        default:
            return "Ethereum"
        }
    }
    
    // MARK: - Private Methods
    
    private func waitForBluetoothReady() async throws {
        guard let manager = centralManager else {
            throw HardwareWalletError.bluetoothDisabled
        }
        
        if manager.state == .poweredOn {
            return
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            var cancellable: AnyCancellable?
            
            let timeout = DispatchWorkItem {
                cancellable?.cancel()
                continuation.resume(throwing: HardwareWalletError.bluetoothDisabled)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)
            
            cancellable = Timer.publish(every: 0.1, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    if self?.centralManager?.state == .poweredOn {
                        timeout.cancel()
                        cancellable?.cancel()
                        continuation.resume()
                    } else if self?.centralManager?.state == .unauthorized {
                        timeout.cancel()
                        cancellable?.cancel()
                        continuation.resume(throwing: HardwareWalletError.bluetoothUnauthorized)
                    }
                }
        }
    }
    
    private func findPeripheral(for device: HWDiscoveredDevice) -> CBPeripheral? {
        // In a real implementation, we'd maintain a map of device IDs to peripherals
        return connectedPeripheral
    }
    
    private func getAddress(derivationPath: String, chain: Chain) async throws -> String {
        let pathComponents = parseDerivationPath(derivationPath)
        let apdu = buildGetAddressAPDU(path: pathComponents, chain: chain)
        
        let response = try await sendAPDU(apdu)
        
        // Parse address from response
        // Format depends on the chain/app
        guard response.count > 0 else {
            throw HardwareWalletError.communicationError("Empty response")
        }
        
        // For Ethereum app: [publicKeyLength (1) | publicKey (65) | addressLength (1) | address (40)]
        if chain.isEVM {
            let pubKeyLength = Int(response[0])
            let addressOffset = 1 + pubKeyLength + 1
            guard response.count > addressOffset else {
                throw HardwareWalletError.communicationError("Invalid response format")
            }
            
            let addressLength = Int(response[addressOffset - 1])
            let addressData = response[addressOffset..<(addressOffset + addressLength)]
            return "0x" + String(data: addressData, encoding: .ascii)!
        }
        
        throw HardwareWalletError.unsupportedChain(chain)
    }
    
    private func parseDerivationPath(_ path: String) -> [UInt32] {
        // Parse "m/44'/60'/0'/0/0" format
        let components = path
            .replacingOccurrences(of: "m/", with: "")
            .split(separator: "/")
        
        return components.compactMap { component in
            let isHardened = component.hasSuffix("'")
            let numberStr = component.replacingOccurrences(of: "'", with: "")
            guard let number = UInt32(numberStr) else { return nil }
            return isHardened ? (number | 0x80000000) : number
        }
    }
    
    private func buildGetAddressAPDU(path: [UInt32], chain: Chain) -> APDU {
        var data = Data()
        data.append(UInt8(path.count))
        
        for component in path {
            var value = component.bigEndian
            data.append(Data(bytes: &value, count: 4))
        }
        
        // Ethereum: CLA=0xE0, INS=0x02 (GET_ADDRESS)
        return APDU(
            cla: 0xE0,
            ins: 0x02,
            p1: 0x00, // Don't display on device
            p2: 0x00, // Return address
            data: data
        )
    }
    
    private func buildSignMessageAPDU(message: Data, path: String, chain: Chain) -> APDU {
        var data = Data()
        
        let pathComponents = parseDerivationPath(path)
        data.append(UInt8(pathComponents.count))
        
        for component in pathComponents {
            var value = component.bigEndian
            data.append(Data(bytes: &value, count: 4))
        }
        
        // Add message length and message
        var messageLength = UInt32(message.count).bigEndian
        data.append(Data(bytes: &messageLength, count: 4))
        data.append(message)
        
        // Ethereum: CLA=0xE0, INS=0x08 (SIGN_PERSONAL_MESSAGE)
        return APDU(
            cla: 0xE0,
            ins: 0x08,
            p1: 0x00,
            p2: 0x00,
            data: data
        )
    }
    
    private func buildSignTypedDataAPDU(typedData: HWTypedData, path: String) -> APDU {
        // Simplified - real implementation would encode full EIP-712 structure
        var data = Data()
        
        let pathComponents = parseDerivationPath(path)
        data.append(UInt8(pathComponents.count))
        
        for component in pathComponents {
            var value = component.bigEndian
            data.append(Data(bytes: &value, count: 4))
        }
        
        // Ethereum: CLA=0xE0, INS=0x0C (SIGN_EIP712_MESSAGE)
        return APDU(
            cla: 0xE0,
            ins: 0x0C,
            p1: 0x00,
            p2: 0x00,
            data: data
        )
    }
    
    private func buildSignTransactionAPDU(transaction: HWTransaction, path: String) -> APDU {
        var data = Data()
        
        let pathComponents = parseDerivationPath(path)
        data.append(UInt8(pathComponents.count))
        
        for component in pathComponents {
            var value = component.bigEndian
            data.append(Data(bytes: &value, count: 4))
        }
        
        // Add RLP-encoded transaction
        let txData = encodeTransaction(transaction)
        data.append(txData)
        
        // Ethereum: CLA=0xE0, INS=0x04 (SIGN_TX)
        return APDU(
            cla: 0xE0,
            ins: 0x04,
            p1: 0x00, // First chunk
            p2: 0x00,
            data: data
        )
    }
    
    private func encodeTransaction(_ tx: HWTransaction) -> Data {
        // Simplified RLP encoding
        var data = Data()
        
        // In a real implementation, this would properly RLP encode the transaction
        // For now, return placeholder
        if let txData = tx.data?.hexToData() {
            data.append(txData)
        }
        
        return data
    }
    
    private func sendAPDU(_ apdu: APDU) async throws -> Data {
        guard let characteristic = writeCharacteristic,
              let peripheral = connectedPeripheral else {
            throw HardwareWalletError.notConnected
        }
        
        let apduData = apdu.encode()
        
        return try await withCheckedThrowingContinuation { continuation in
            self.pendingResponse = continuation
            self.responseBuffer = Data()
            
            // Frame the APDU for Ledger BLE transport
            let framedData = frameAPDU(apduData)
            
            for frame in framedData {
                peripheral.writeValue(frame, for: characteristic, type: .withResponse)
            }
        }
    }
    
    private func frameAPDU(_ apdu: Data) -> [Data] {
        // Ledger BLE uses a framing protocol
        // MTU is typically 20 bytes for BLE
        let mtu = 20
        var frames: [Data] = []
        var offset = 0
        var sequence: UInt16 = 0
        
        while offset < apdu.count {
            var frame = Data()
            
            if sequence == 0 {
                // First frame includes length
                frame.append(0x05) // Channel ID high
                frame.append(0x00) // Channel ID low
                frame.append(UInt8((sequence >> 8) & 0xFF))
                frame.append(UInt8(sequence & 0xFF))
                frame.append(UInt8((apdu.count >> 8) & 0xFF))
                frame.append(UInt8(apdu.count & 0xFF))
            } else {
                frame.append(0x05)
                frame.append(0x00)
                frame.append(UInt8((sequence >> 8) & 0xFF))
                frame.append(UInt8(sequence & 0xFF))
            }
            
            let remaining = apdu.count - offset
            let chunkSize = min(remaining, mtu - frame.count)
            frame.append(apdu[offset..<(offset + chunkSize)])
            
            // Pad to MTU
            while frame.count < mtu {
                frame.append(0x00)
            }
            
            frames.append(frame)
            offset += chunkSize
            sequence += 1
        }
        
        return frames
    }
    
    private func handleReceivedData(_ data: Data) {
        // Unframe and accumulate response
        guard data.count >= 5 else { return }
        
        let sequence = (UInt16(data[2]) << 8) | UInt16(data[3])
        
        if sequence == 0 {
            // First frame - contains length
            let length = (Int(data[4]) << 8) | Int(data[5])
            responseBuffer = Data()
            responseBuffer.append(data[6...])
            
            if responseBuffer.count >= length {
                completeResponse()
            }
        } else {
            responseBuffer.append(data[4...])
            
            // Check if we have complete response
            // In real implementation, we'd track expected length
            if data.last == 0x90 && data[data.count - 2] == 0x00 {
                completeResponse()
            }
        }
    }
    
    private func completeResponse() {
        // Check status word (last 2 bytes)
        guard responseBuffer.count >= 2 else {
            pendingResponse?.resume(throwing: HardwareWalletError.communicationError("Invalid response"))
            pendingResponse = nil
            return
        }
        
        let sw1 = responseBuffer[responseBuffer.count - 2]
        let sw2 = responseBuffer[responseBuffer.count - 1]
        
        if sw1 == 0x90 && sw2 == 0x00 {
            // Success
            let response = responseBuffer.dropLast(2)
            pendingResponse?.resume(returning: Data(response))
        } else {
            // Error
            let error = interpretStatusWord(sw1: sw1, sw2: sw2)
            pendingResponse?.resume(throwing: error)
        }
        
        pendingResponse = nil
    }
    
    private func interpretStatusWord(sw1: UInt8, sw2: UInt8) -> HardwareWalletError {
        switch (sw1, sw2) {
        case (0x69, 0x85):
            return .userCancelled
        case (0x68, 0x00):
            return .appNotOpen("Required app")
        case (0x6B, 0x00):
            return .invalidTransaction
        case (0x6D, 0x00):
            return .unsupportedOperation
        default:
            return .communicationError(String(format: "Status: %02X%02X", sw1, sw2))
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension LedgerService: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                break
            case .poweredOff:
                connectionState = .disconnected
                lastError = .bluetoothDisabled
            case .unauthorized:
                connectionState = .error
                lastError = .bluetoothUnauthorized
            default:
                break
            }
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown Ledger"
        
        let device = HWDiscoveredDevice(
            id: peripheral.identifier.uuidString,
            name: name,
            type: .ledger,
            model: detectModel(from: name),
            connectionMethod: .bluetooth,
            rssi: RSSI.intValue
        )
        
        Task { @MainActor in
            if !discoveredDevices.contains(where: { $0.id == device.id }) {
                discoveredDevices.append(device)
            }
            
            // Auto-connect to first device found
            if connectedPeripheral == nil {
                connectedPeripheral = peripheral
                try? await connect(to: device)
            }
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices([ledgerServiceUUID])
        
        Task { @MainActor in
            connectionState = .connecting
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            connectionState = .error
            lastError = .connectionFailed(error?.localizedDescription ?? "Unknown error")
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            connectionState = .disconnected
            isConnected = false
            connectedDevice = nil
        }
    }
    
    private func detectModel(from name: String) -> String? {
        if name.contains("Nano X") {
            return "Nano X"
        } else if name.contains("Nano S Plus") {
            return "Nano S Plus"
        } else if name.contains("Stax") {
            return "Stax"
        }
        return nil
    }
}

// MARK: - CBPeripheralDelegate

extension LedgerService: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == ledgerServiceUUID }) else {
            Task { @MainActor in
                connectionState = .error
                lastError = .connectionFailed("Ledger service not found")
            }
            return
        }
        
        peripheral.discoverCharacteristics([writeCharacteristicUUID, notifyCharacteristicUUID], for: service)
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        
        for characteristic in characteristics {
            if characteristic.uuid == writeCharacteristicUUID {
                writeCharacteristic = characteristic
            } else if characteristic.uuid == notifyCharacteristicUUID {
                notifyCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
        
        // Check if we have both characteristics
        if writeCharacteristic != nil && notifyCharacteristic != nil {
            Task { @MainActor in
                connectionState = .connected
                isConnected = true
                
                if let device = discoveredDevices.first(where: { $0.id == peripheral.identifier.uuidString }) {
                    connectedDevice = device
                }
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == notifyCharacteristicUUID,
              let data = characteristic.value else { return }
        
        handleReceivedData(data)
    }
}

// MARK: - APDU

/// Application Protocol Data Unit for Ledger communication
public struct APDU {
    let cla: UInt8
    let ins: UInt8
    let p1: UInt8
    let p2: UInt8
    let data: Data
    
    func encode() -> Data {
        var result = Data()
        result.append(cla)
        result.append(ins)
        result.append(p1)
        result.append(p2)
        result.append(UInt8(data.count))
        result.append(data)
        return result
    }
}

// MARK: - Ledger Models

public struct LedgerApp: Codable, Equatable {
    public let name: String
    public let version: String
}

public struct LedgerDeviceInfo: Codable, Equatable {
    public let model: String
    public let firmwareVersion: String
    public let seVersion: String?
}


// MARK: - String Extension

private extension String {
    func hexToData() -> Data? {
        var hex = self
        if hex.hasPrefix("0x") {
            hex = String(hex.dropFirst(2))
        }
        
        var data = Data()
        var index = hex.startIndex
        
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            if let byte = UInt8(hex[index..<nextIndex], radix: 16) {
                data.append(byte)
            }
            index = nextIndex
        }
        
        return data
    }
}
