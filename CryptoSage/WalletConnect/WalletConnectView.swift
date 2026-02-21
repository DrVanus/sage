//
//  WalletConnectView.swift
//  CryptoSage
//
//  WalletConnect UI for connecting mobile wallets.
//

import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - WalletConnect View

struct WalletConnectView: View {
    @StateObject private var walletConnect = WalletConnectService.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var showQRCode = false
    @State private var connectionURI: String?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if walletConnect.isConnected, let account = walletConnect.connectedAccount {
                        connectedView(account: account)
                    } else if showQRCode, let uri = connectionURI {
                        qrCodeView(uri: uri)
                    } else {
                        walletSelectionView
                    }
                }
                .padding()
            }
            .background(DS.Adaptive.background.ignoresSafeArea())
            .navigationTitle("Connect Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(BrandColors.goldBase)
                }
            }
        }
    }
    
    // MARK: - Wallet Selection View
    
    private var walletSelectionView: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(BrandColors.goldBase.opacity(0.15))
                        .frame(width: 80, height: 80)
                    Image(systemName: "wallet.pass.fill")
                        .font(.system(size: 36))
                        .foregroundColor(BrandColors.goldBase)
                }
                
                Text("Connect Your Wallet")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text("Connect a mobile wallet to view balances and trade on prediction markets.")
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 20)
            
            // QR Code Option
            Button {
                Task { await generateQRCode() }
            } label: {
                HStack {
                    Image(systemName: "qrcode")
                        .font(.title2)
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Scan QR Code")
                            .font(.headline)
                            .foregroundColor(DS.Adaptive.textPrimary)
                        Text("Open your wallet app and scan")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .padding()
                .background(DS.Adaptive.cardBackground)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(DS.Adaptive.stroke, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(walletConnect.isConnecting)
            
            // Popular Wallets
            VStack(alignment: .leading, spacing: 16) {
                Text("Popular Wallets")
                    .font(.headline)
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(SupportedWallet.all) { wallet in
                        walletButton(wallet)
                    }
                }
            }
            
            // Info
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(.green)
                    Text("Secure Connection")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.green)
                }
                
                Text("CryptoSage never has access to your private keys. Connections are encrypted and you can disconnect at any time.")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .background(Color.green.opacity(0.1))
            .cornerRadius(12)
        }
    }
    
    private func walletButton(_ wallet: SupportedWallet) -> some View {
        Button {
            openWallet(wallet)
        } label: {
            VStack(spacing: 8) {
                // Wallet icon placeholder
                Circle()
                    .fill(DS.Adaptive.chipBackground)
                    .frame(width: 48, height: 48)
                    .overlay {
                        Text(String(wallet.name.prefix(1)))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                
                Text(wallet.name)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundColor(DS.Adaptive.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(DS.Adaptive.cardBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(DS.Adaptive.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - QR Code View
    
    private func qrCodeView(uri: String) -> some View {
        VStack(spacing: 24) {
            Text("Scan with your wallet")
                .font(.headline)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            // QR Code
            if let qrImage = generateQRCodeImage(from: uri) {
                Image(uiImage: qrImage)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 250, height: 250)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(16)
            }
            
            // Copy URI button
            Button {
                UIPasteboard.general.string = uri
            } label: {
                Label("Copy Link", systemImage: "doc.on.doc")
                    .foregroundColor(BrandColors.goldBase)
            }
            .buttonStyle(.bordered)
            .tint(BrandColors.goldBase)
            
            // Instructions
            VStack(alignment: .leading, spacing: 12) {
                instructionRow(number: 1, text: "Open your wallet app")
                instructionRow(number: 2, text: "Tap the scan or WalletConnect button")
                instructionRow(number: 3, text: "Scan this QR code")
                instructionRow(number: 4, text: "Approve the connection")
            }
            .padding()
            .background(DS.Adaptive.cardBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(DS.Adaptive.stroke, lineWidth: 1)
            )
            
            // Back button
            Button("Choose Different Wallet") {
                showQRCode = false
                connectionURI = nil
            }
            .font(.subheadline)
        }
    }
    
    private func instructionRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .frame(width: 24, height: 24)
                .background(BrandColors.goldBase)
                .foregroundColor(.black)
                .clipShape(Circle())
            
            Text(text)
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textPrimary)
        }
    }
    
    // MARK: - Connected View
    
    private func connectedView(account: WalletConnectAccount) -> some View {
        VStack(spacing: 24) {
            // Success indicator
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.green)
            
            Text("Wallet Connected")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            // Account info
            VStack(spacing: 12) {
                HStack {
                    Text("Address")
                        .foregroundColor(DS.Adaptive.textSecondary)
                    Spacer()
                    Text(formatAddress(account.address))
                        .fontWeight(.medium)
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                
                if let chain = account.chain {
                    HStack {
                        Text("Network")
                            .foregroundColor(DS.Adaptive.textSecondary)
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: chain.iconName)
                                .foregroundColor(chain.brandColor)
                            Text(chain.displayName)
                                .fontWeight(.medium)
                                .foregroundColor(DS.Adaptive.textPrimary)
                        }
                    }
                }
            }
            .padding()
            .background(DS.Adaptive.cardBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(DS.Adaptive.stroke, lineWidth: 1)
            )
            
            // Actions
            VStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(BrandColors.goldBase)
                        .cornerRadius(12)
                }
                
                Button(role: .destructive) {
                    Task {
                        try? await walletConnect.disconnect()
                    }
                } label: {
                    Text("Disconnect")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(DS.Adaptive.cardBackground)
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                        )
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func generateQRCode() async {
        do {
            let uri = try await walletConnect.connect()
            await MainActor.run {
                connectionURI = uri
                showQRCode = true
            }
        } catch {
            // Handle error
        }
    }
    
    private func openWallet(_ wallet: SupportedWallet) {
        Task {
            // First generate the URI
            guard let uri = try? await walletConnect.connect() else { return }
            
            // Encode URI for URL
            guard let encodedURI = uri.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
            
            // Try deep link first, then universal link
            var urlString: String?
            
            if let deepLink = wallet.deepLink {
                urlString = "\(deepLink)wc?uri=\(encodedURI)"
            } else if let universalLink = wallet.universalLink {
                urlString = "\(universalLink)/wc?uri=\(encodedURI)"
            }
            
            if let urlString = urlString, let url = URL(string: urlString) {
                await MainActor.run {
                    UIApplication.shared.open(url)
                }
            }
            
            // Show QR code as fallback
            await MainActor.run {
                connectionURI = uri
                showQRCode = true
            }
        }
    }
    
    // MARK: - Helpers
    
    private func formatAddress(_ address: String) -> String {
        guard address.count > 10 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }
    
    private func generateQRCodeImage(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        
        guard let outputImage = filter.outputImage else { return nil }
        
        // Scale up for better quality
        let scale = UIScreen.main.scale * 4
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaledImage = outputImage.transformed(by: transform)
        
        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - WalletConnect Button (for use in other views)

struct WalletConnectButton: View {
    @StateObject private var walletConnect = WalletConnectService.shared
    @State private var showConnectSheet = false
    
    var body: some View {
        Button {
            showConnectSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: walletConnect.isConnected ? "checkmark.circle.fill" : "wallet.pass")
                    .foregroundColor(walletConnect.isConnected ? .green : BrandColors.goldBase)
                
                if walletConnect.isConnected {
                    if let account = walletConnect.connectedAccount {
                        Text(formatAddress(account.address))
                            .font(.subheadline)
                            .foregroundColor(DS.Adaptive.textPrimary)
                    }
                } else {
                    Text("Connect Wallet")
                        .font(.subheadline)
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(DS.Adaptive.chipBackground)
            .cornerRadius(20)
            .overlay(
                Capsule()
                    .stroke(DS.Adaptive.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showConnectSheet) {
            WalletConnectView()
        }
    }
    
    private func formatAddress(_ address: String) -> String {
        guard address.count > 10 else { return address }
        return "\(address.prefix(4))...\(address.suffix(4))"
    }
}

// MARK: - Preview

#Preview {
    WalletConnectView()
}
