//
//  TrezorSetupView.swift
//  CryptoSage
//
//  Trezor device setup and connection flow using Trezor Suite deep linking.
//

import SwiftUI

struct TrezorSetupView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var trezorService = HardwareWalletManager.shared.trezorService
    
    @State private var currentStep: SetupStep = .instructions
    @State private var addressInput = ""
    @State private var selectedChain: Chain = .ethereum
    @State private var isConnecting = false
    @State private var errorMessage: String?
    
    enum SetupStep {
        case instructions
        case connect
        case addAccount
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
            .navigationTitle("Connect Trezor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Text("Cancel")
                            .foregroundStyle(DS.Adaptive.textSecondary)
                    }
                }
            }
        }
    }
    
    private var progressIndicator: some View {
        HStack(spacing: 4) {
            ForEach(0..<4) { index in
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
        case .connect: return 1
        case .addAccount: return 2
        case .complete: return 3
        }
    }
    
    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case .instructions:
            instructionsContent
        case .connect:
            connectContent
        case .addAccount:
            addAccountContent
        case .complete:
            completeContent
        }
    }
    
    private var instructionsContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "lock.shield")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            
            Text("Connect Your Trezor")
                .font(.title2.bold())
            
            VStack(alignment: .leading, spacing: 16) {
                instructionRow(number: 1, text: "Connect your Trezor to your computer via USB")
                instructionRow(number: 2, text: "Open Trezor Suite on your computer")
                instructionRow(number: 3, text: "Unlock your device with your PIN")
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color(white: 0.1) : .white)
            }
            
            VStack(spacing: 8) {
                Text("Note: Trezor connection requires Trezor Suite")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Link(destination: URL(string: "https://suite.trezor.io")!) {
                    HStack {
                        Image(systemName: "arrow.down.circle")
                        Text("Download Trezor Suite")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.accentColor)
                }
            }
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
    
    private var connectContent: some View {
        VStack(spacing: 24) {
            if isConnecting {
                ProgressView()
                    .scaleEffect(2)
                    .frame(height: 60)
                
                Text("Connecting to Trezor Bridge...")
                    .font(.title3.weight(.semibold))
            } else if trezorService.isConnected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                
                Text("Trezor Connected!")
                    .font(.title3.weight(.semibold))
                
                if let device = trezorService.connectedDevice {
                    Text(device.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)
                    
                    Text("Trezor Bridge Not Found")
                        .font(.title3.weight(.semibold))
                    
                    Text("Make sure Trezor Suite is running on your computer and connected to the same network.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Divider()
                    
                    Text("Alternative: Import Manually")
                        .font(.headline)
                    
                    Text("You can manually enter your Trezor wallet address to track it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    private var addAccountContent: some View {
        VStack(spacing: 24) {
            Text("Add Trezor Account")
                .font(.title2.bold())
            
            Text("Enter your wallet address or use Trezor Suite to sign in")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            // Chain selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Select Chain")
                    .font(.subheadline.weight(.medium))
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(trezorService.supportedChains, id: \.self) { chain in
                            Button {
                                selectedChain = chain
                            } label: {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(chain.brandColor)
                                        .frame(width: 20, height: 20)
                                        .overlay {
                                            Text(chain.nativeSymbol.prefix(1))
                                                .font(.caption2.bold())
                                                .foregroundStyle(.white)
                                        }
                                    
                                    Text(chain.displayName)
                                        .font(.caption.weight(.medium))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background {
                                    Capsule()
                                        .fill(selectedChain == chain ? Color.accentColor : Color.secondary.opacity(0.15))
                                }
                                .foregroundStyle(selectedChain == chain ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            
            // Address input
            VStack(alignment: .leading, spacing: 8) {
                Text("Wallet Address")
                    .font(.subheadline.weight(.medium))
                
                TextField("0x...", text: $addressInput)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding()
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(colorScheme == .dark ? Color(white: 0.1) : .white)
                    }
            }
            
            // Open Trezor Suite
            VStack(spacing: 12) {
                Text("Or get address from Trezor Suite")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Button {
                    openTrezorSuite()
                } label: {
                    HStack {
                        Image(systemName: "arrow.up.forward.app")
                        Text("Open Trezor Suite")
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.accentColor.opacity(0.1))
                    .foregroundColor(.accentColor)
                    .clipShape(Capsule())
                }
            }
        }
    }
    
    private var completeContent: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            
            Text("Account Added!")
                .font(.title2.bold())
            
            Text("Your Trezor account has been imported. You can now track its balances and sign transactions.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            VStack(alignment: .leading, spacing: 8) {
                Label("\(selectedChain.displayName) network", systemImage: "network")
                Label("Address tracked", systemImage: "eye")
                Label("Ready for signing", systemImage: "signature")
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
            
            if currentStep == .connect && !trezorService.isConnected {
                Button("Import Manually Instead") {
                    currentStep = .addAccount
                }
                .font(.subheadline)
                .foregroundColor(.accentColor)
            }
        }
        .padding()
        .background(colorScheme == .dark ? Color(white: 0.1) : .white)
    }
    
    private var actionButtonTitle: String {
        switch currentStep {
        case .instructions: return "Continue"
        case .connect:
            if isConnecting { return "Connecting..." }
            if trezorService.isConnected { return "Continue" }
            return "Try Again"
        case .addAccount: return addressInput.isEmpty ? "Skip" : "Import Account"
        case .complete: return "Done"
        }
    }
    
    private var actionButtonDisabled: Bool {
        currentStep == .connect && isConnecting
    }
    
    private func handleAction() {
        switch currentStep {
        case .instructions:
            currentStep = .connect
            tryConnect()
        case .connect:
            if trezorService.isConnected {
                currentStep = .addAccount
            } else {
                tryConnect()
            }
        case .addAccount:
            if !addressInput.isEmpty {
                importAccount()
            }
            currentStep = .complete
        case .complete:
            dismiss()
        }
    }
    
    private func tryConnect() {
        isConnecting = true
        errorMessage = nil
        
        Task {
            do {
                try await trezorService.connect()
                await MainActor.run {
                    isConnecting = false
                }
            } catch {
                await MainActor.run {
                    isConnecting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    private func openTrezorSuite() {
        if let url = trezorService.openTrezorSuite(for: .getAddress(path: HWDerivationPath.ethereum(), chain: selectedChain)) {
            #if os(iOS)
            UIApplication.shared.open(url)
            #endif
        }
    }
    
    private func importAccount() {
        guard !addressInput.isEmpty else { return }
        
        let path = HWDerivationPath.defaultPath(for: selectedChain)
        trezorService.importAccount(
            address: addressInput,
            chain: selectedChain,
            path: path
        )
    }
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color(white: 0.05) : Color(white: 0.96)
    }
}

#Preview {
    TrezorSetupView()
}
