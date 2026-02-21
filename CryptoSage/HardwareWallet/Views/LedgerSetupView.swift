//
//  LedgerSetupView.swift
//  CryptoSage
//
//  Ledger device setup and connection flow.
//

import SwiftUI

struct LedgerSetupView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var ledgerService = HardwareWalletManager.shared.ledgerService
    
    @State private var currentStep: SetupStep = .instructions
    @State private var selectedChain: Chain = .ethereum
    @State private var fetchedAccounts: [HWAccount] = []
    @State private var selectedAccounts: Set<String> = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    enum SetupStep {
        case instructions
        case scanning
        case connecting
        case selectApp
        case selectAccounts
        case complete
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress
                progressIndicator
                
                // Content
                ScrollView {
                    VStack(spacing: 24) {
                        stepContent
                    }
                    .padding()
                }
                
                // Bottom Action
                bottomAction
            }
            .background(backgroundColor)
            .navigationTitle("Connect Ledger")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Text("Cancel")
                            .foregroundStyle(DS.Adaptive.textSecondary)
                    }
                }
            }
            .onChange(of: ledgerService.connectionState) { _, newState in
                handleConnectionStateChange(newState)
            }
        }
    }
    
    private var progressIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<5) { index in
                Rectangle()
                    .fill(stepIndex >= index ? Color.accentColor : Color.secondary.opacity(0.2))
                    .frame(height: 3)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    private var stepIndex: Int {
        switch currentStep {
        case .instructions: return 0
        case .scanning: return 1
        case .connecting: return 2
        case .selectApp: return 3
        case .selectAccounts: return 4
        case .complete: return 5
        }
    }
    
    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .instructions:
            instructionsContent
        case .scanning:
            scanningContent
        case .connecting:
            connectingContent
        case .selectApp:
            selectAppContent
        case .selectAccounts:
            selectAccountsContent
        case .complete:
            completeContent
        }
    }
    
    private var instructionsContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 64))
                .foregroundStyle(.blue)
            
            Text("Connect Your Ledger")
                .font(.title2.bold())
            
            VStack(alignment: .leading, spacing: 16) {
                instructionRow(number: 1, text: "Make sure your Ledger Nano X is charged and unlocked")
                instructionRow(number: 2, text: "Enable Bluetooth in your device settings")
                instructionRow(number: 3, text: "Open the app for the chain you want to use (e.g., Ethereum)")
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color(white: 0.1) : .white)
            }
            
            Text("Note: Only Ledger Nano X and Ledger Stax support Bluetooth connection")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private func instructionRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 24, height: 24)
                
                Text("\(number)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
            }
            
            Text(text)
                .font(.subheadline)
        }
    }
    
    private var scanningContent: some View {
        VStack(spacing: 24) {
            scanningIndicator
            scanningText
            discoveredDevicesSection
            scanningErrorSection
        }
    }
    
    private var scanningIndicator: some View {
        ZStack {
            ForEach(0..<3) { i in
                Circle()
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 2)
                    .frame(width: CGFloat(100 + i * 50), height: CGFloat(100 + i * 50))
            }
            
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)
        }
        .frame(height: 200)
    }
    
    private var scanningText: some View {
        VStack(spacing: 8) {
            Text("Scanning for Devices...")
                .font(.title3.weight(.semibold))
            
            Text("Make sure your Ledger is nearby with Bluetooth enabled")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    @ViewBuilder
    private var discoveredDevicesSection: some View {
        if !ledgerService.discoveredDevices.isEmpty {
            VStack(spacing: 8) {
                Text("Found Devices")
                    .font(.headline)
                
                ForEach(ledgerService.discoveredDevices) { device in
                    discoveredDeviceButton(device)
                }
            }
        }
    }
    
    private func discoveredDeviceButton(_ device: HWDiscoveredDevice) -> some View {
        Button {
            connectToDevice(device)
        } label: {
            HStack {
                Image(systemName: "checkmark.shield")
                    .foregroundColor(.green)
                
                Text(device.displayName)
                    .font(.subheadline.weight(.medium))
                
                Spacer()
                
                if let rssi = device.rssi {
                    signalStrength(rssi: rssi)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color(white: 0.1) : Color.white)
            )
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var scanningErrorSection: some View {
        if let error = errorMessage {
            Text(error)
                .font(.caption)
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
        }
    }
    
    private func signalStrength(rssi: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<4) { i in
                Rectangle()
                    .fill(rssi > -70 + (i * 10) ? Color.green : Color.secondary.opacity(0.3))
                    .frame(width: 4, height: CGFloat(8 + i * 3))
            }
        }
    }
    
    private var connectingContent: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(2)
                .frame(height: 60)
            
            Text("Connecting...")
                .font(.title3.weight(.semibold))
            
            Text("Please wait while we establish a secure connection")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
    
    private var selectAppContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "app.badge")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            
            Text("Select Chain")
                .font(.title2.bold())
            
            Text("Choose which blockchain you want to use. Make sure the corresponding app is open on your Ledger.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(ledgerService.supportedChains, id: \.self) { chain in
                    chainOption(chain)
                }
            }
            
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.caption)
                Text("Open the \(ledgerService.appName(for: selectedChain)) app on your Ledger")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
    }
    
    private func chainOption(_ chain: Chain) -> some View {
        let isSelected = selectedChain == chain
        let bgColor: Color = isSelected ? Color.accentColor.opacity(0.1) : (colorScheme == .dark ? Color(white: 0.1) : Color.white)
        let strokeColor: Color = isSelected ? Color.accentColor : Color.clear
        
        return Button {
            selectedChain = chain
        } label: {
            chainOptionLabel(chain: chain, isSelected: isSelected)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(bgColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(strokeColor, lineWidth: 2)
                        )
                )
        }
        .buttonStyle(.plain)
    }
    
    private func chainOptionLabel(chain: Chain, isSelected: Bool) -> some View {
        HStack {
            Circle()
                .fill(chain.brandColor)
                .frame(width: 32, height: 32)
                .overlay(
                    Text(String(chain.nativeSymbol.prefix(1)))
                        .font(.caption.bold())
                        .foregroundColor(.white)
                )
            
            Text(chain.displayName)
                .font(.subheadline.weight(.medium))
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.accentColor)
            }
        }
    }
    
    private var selectAccountsContent: some View {
        VStack(spacing: 24) {
            if isLoading {
                ProgressView("Fetching accounts...")
            } else {
                Text("Select Accounts")
                    .font(.title2.bold())
                
                Text("Choose which accounts to import into CryptoSage")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                ForEach(fetchedAccounts) { account in
                    accountRow(account)
                }
                
                if fetchedAccounts.isEmpty {
                    Text("No accounts found. Make sure the app is open on your Ledger.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }
    
    private func accountRow(_ account: HWAccount) -> some View {
        Button {
            if selectedAccounts.contains(account.id) {
                selectedAccounts.remove(account.id)
            } else {
                selectedAccounts.insert(account.id)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(account.displayName)
                        .font(.subheadline.weight(.medium))
                    
                    Text(account.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                
                Spacer()
                
                Image(systemName: selectedAccounts.contains(account.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(selectedAccounts.contains(account.id) ? .accentColor : .secondary)
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color(white: 0.1) : .white)
            }
        }
        .buttonStyle(.plain)
    }
    
    private var completeContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            
            Text("Connection Successful!")
                .font(.title2.bold())
            
            Text("Your Ledger is now connected. You can use it to sign transactions securely.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 8) {
                Label("\(selectedAccounts.count) accounts imported", systemImage: "person.2")
                Label("\(selectedChain.displayName) network", systemImage: "network")
                Label("Secure signing enabled", systemImage: "lock.shield")
            }
            .font(.subheadline)
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color(white: 0.1) : .white)
            }
        }
    }
    
    private var bottomAction: some View {
        VStack(spacing: 12) {
            Button {
                handleAction()
            } label: {
                Text(actionButtonTitle)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(actionButtonDisabled ? Color.secondary : Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(actionButtonDisabled)
        }
        .padding()
        .background(colorScheme == .dark ? Color(white: 0.1) : .white)
    }
    
    private var actionButtonTitle: String {
        switch currentStep {
        case .instructions: return "Start Scanning"
        case .scanning: return "Scanning..."
        case .connecting: return "Connecting..."
        case .selectApp: return "Continue"
        case .selectAccounts: return selectedAccounts.isEmpty ? "Skip" : "Import \(selectedAccounts.count) Accounts"
        case .complete: return "Done"
        }
    }
    
    private var actionButtonDisabled: Bool {
        switch currentStep {
        case .scanning, .connecting: return true
        default: return false
        }
    }
    
    private func handleAction() {
        switch currentStep {
        case .instructions:
            currentStep = .scanning
            startScanning()
        case .selectApp:
            currentStep = .selectAccounts
            fetchAccounts()
        case .selectAccounts:
            importSelectedAccounts()
            currentStep = .complete
        case .complete:
            dismiss()
        default:
            break
        }
    }
    
    private func startScanning() {
        Task {
            await ledgerService.startScanning()
        }
    }
    
    private func connectToDevice(_ device: HWDiscoveredDevice) {
        currentStep = .connecting
        Task {
            do {
                try await ledgerService.connect(to: device)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    currentStep = .scanning
                }
            }
        }
    }
    
    private func handleConnectionStateChange(_ state: HWConnectionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                currentStep = .selectApp
            case .error:
                errorMessage = ledgerService.lastError?.localizedDescription
                currentStep = .scanning
            default:
                break
            }
        }
    }
    
    private func fetchAccounts() {
        isLoading = true
        Task {
            do {
                let accounts = try await ledgerService.getAccounts(for: selectedChain)
                await MainActor.run {
                    fetchedAccounts = accounts
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
    
    private func importSelectedAccounts() {
        let accountsToImport = fetchedAccounts.filter { selectedAccounts.contains($0.id) }
        for account in accountsToImport {
            HardwareWalletManager.shared.importAccount(account)
        }
    }
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color(white: 0.05) : Color(white: 0.96)
    }
}

#Preview {
    LedgerSetupView()
}
