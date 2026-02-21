//
//  MultiChainWalletView.swift
//  CryptoSage
//
//  Premium view for connecting and managing multi-chain wallets.
//  Features enhanced blockchain icons and premium UI design.
//

import SwiftUI

// MARK: - Multi-Chain Wallet View

struct MultiChainWalletView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var multiChainVM = MultiChainPortfolioViewModel.shared
    
    @State private var showingAddWallet = false
    @State private var showingHardwareWallet = false
    @State private var selectedChain: Chain?
    @State private var walletAddress = ""
    @State private var walletName = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var appeared = false
    
    private let chainRegistry = ChainRegistry.shared
    private let cardCornerRadius: CGFloat = 16
    
    /// Gold gradient for header buttons
    private var chipGoldGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    var body: some View {
        ZStack {
            // Premium background
            FuturisticBackground()
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Add New Wallet Section
                    addWalletSection
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(.easeOut(duration: 0.4).delay(0.1), value: appeared)
                    
                    // Connected Wallets Section
                    if !multiChainVM.connectedWallets.isEmpty {
                        connectedWalletsSection
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 20)
                            .animation(.easeOut(duration: 0.4).delay(0.15), value: appeared)
                    }
                    
                    // Supported Chains Section
                    supportedChainsSection
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(.easeOut(duration: 0.4).delay(0.2), value: appeared)
                }
                .padding()
                .padding(.bottom, 20)
            }
        }
        .navigationTitle("DeFi Wallets")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                }
                .fontWeight(.medium)
                .foregroundStyle(chipGoldGradient)
            }
        }
        .refreshable {
            await multiChainVM.refreshAllWallets()
        }
        .sheet(isPresented: $showingAddWallet) {
            addWalletSheet
        }
        .sheet(isPresented: $showingHardwareWallet) {
            HardwareWalletConnectionView()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                appeared = true
            }
        }
    }
    
    // MARK: - Add Wallet Section
    
    private var addWalletSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Wallet")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(DS.Adaptive.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 4)
            
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showingAddWallet = true
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: colorScheme == .dark
                                        ? [Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.3), Color.orange.opacity(0.15)]
                                        : [.blue.opacity(0.2), .blue.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: colorScheme == .dark
                                        ? [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange]
                                        : [.blue, .blue.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Connect New Wallet")
                            .font(.headline)
                            .foregroundColor(DS.Adaptive.textPrimary)
                        Text("Track tokens, NFTs, and DeFi positions")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .padding(16)
                .background(premiumCardBackground)
            }
            .buttonStyle(.plain)
            
            // Hardware Wallet Option
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showingHardwareWallet = true
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: colorScheme == .dark
                                        ? [Color.purple.opacity(0.3), Color.blue.opacity(0.15)]
                                        : [.purple.opacity(0.2), .blue.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 48, height: 48)
                        
                        Image(systemName: "shield.checkered")
                            .font(.title2)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.purple, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("Hardware Wallet")
                                .font(.headline)
                                .foregroundColor(DS.Adaptive.textPrimary)
                            
                            Text("SECURE")
                                .font(.caption2.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    LinearGradient(
                                        colors: [.purple, .blue],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .clipShape(Capsule())
                        }
                        Text("Connect Ledger or Trezor")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
                .padding(16)
                .background(premiumCardBackground)
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Connected Wallets Section
    
    private var connectedWalletsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Connected Wallets")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                Spacer()
                
                Text("\(multiChainVM.connectedWallets.count)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        LinearGradient(
                            colors: [.green, .green.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 4)
            
            VStack(spacing: 0) {
                ForEach(Array(multiChainVM.connectedWallets.enumerated()), id: \.element.id) { index, wallet in
                    connectedWalletRow(wallet)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                multiChainVM.disconnectWallet(id: wallet.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    
                    if index < multiChainVM.connectedWallets.count - 1 {
                        Rectangle()
                            .fill(DS.Adaptive.divider)
                            .frame(height: 1)
                            .padding(.leading, 66)
                    }
                }
            }
            .background(premiumCardBackground)
            
            Text("Swipe left to remove a wallet. Your data is stored locally.")
                .font(.caption)
                .foregroundColor(DS.Adaptive.textTertiary)
                .padding(.horizontal, 4)
        }
    }
    
    // MARK: - Supported Chains Section
    
    private var supportedChainsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Supported Chains")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(DS.Adaptive.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 4)
            
            VStack(spacing: 0) {
                ForEach(Array(chainRegistry.supportedChains.enumerated()), id: \.element.rawValue) { index, chain in
                    chainRow(chain)
                    
                    if index < chainRegistry.supportedChains.count - 1 {
                        Rectangle()
                            .fill(DS.Adaptive.divider)
                            .frame(height: 1)
                            .padding(.leading, 58)
                    }
                }
            }
            .background(premiumCardBackground)
            
            Text("Connect wallets from any of these networks. Token balances and NFTs will be automatically tracked.")
                .font(.caption)
                .foregroundColor(DS.Adaptive.textTertiary)
                .padding(.horizontal, 4)
        }
    }
    
    // MARK: - Connected Wallet Row
    
    private func connectedWalletRow(_ wallet: ConnectedChainWallet) -> some View {
        let chain = Chain(rawValue: wallet.chainId)
        
        return HStack(spacing: 14) {
            PremiumChainIcon(chain: chain, size: 44)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(wallet.name ?? shortenAddress(wallet.address))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                HStack(spacing: 8) {
                    Text(chain?.displayName ?? wallet.chainId)
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    if !wallet.tokenBalances.isEmpty {
                        Text("•")
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Text("\(wallet.tokenBalances.count) tokens")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                    
                    if let nftCount = wallet.nftCount, nftCount > 0 {
                        Text("•")
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Text("\(nftCount) NFTs")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                }
                
                Text(shortenAddress(wallet.address))
                    .font(.caption2)
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .monospaced()
            }
            
            Spacer()
            
            if let value = wallet.totalValueUSD {
                Text(formatCurrency(value))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
            }
        }
        .padding(16)
        .contentShape(Rectangle())
    }
    
    // MARK: - Chain Row
    
    private func chainRow(_ chain: Chain) -> some View {
        HStack(spacing: 14) {
            PremiumChainIcon(chain: chain, size: 40)
            
            Text(chain.displayName)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Spacer()
            
            let connectedCount = multiChainVM.connectedWallets.filter { $0.chainId == chain.rawValue }.count
            if connectedCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.green)
                    Text("\(connectedCount)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.green.opacity(0.15))
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
    
    // MARK: - Add Wallet Sheet
    
    private var addWalletSheet: some View {
        NavigationStack {
            ZStack {
                FuturisticBackground()
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Chain Selection
                        chainSelectionSection
                        
                        // Wallet Details
                        walletDetailsSection
                        
                        // Connect Button
                        connectButton
                        
                        // Error Message
                        if let error = errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text(error)
                                    .font(.subheadline)
                                    .foregroundColor(.red)
                            }
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.red.opacity(0.1))
                            )
                        }
                    }
                    .padding()
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Add Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showingAddWallet = false
                        resetForm()
                    }
                    .foregroundStyle(chipGoldGradient)
                }
            }
        }
    }
    
    private var chainSelectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Chain")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(DS.Adaptive.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 4)
            
            VStack(spacing: 0) {
                ForEach(Array(chainRegistry.supportedChains.enumerated()), id: \.element.rawValue) { index, chain in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        selectedChain = chain
                    } label: {
                        HStack(spacing: 14) {
                            PremiumChainIcon(chain: chain, size: 36)
                            
                            Text(chain.displayName)
                                .font(.subheadline)
                                .foregroundColor(DS.Adaptive.textPrimary)
                            
                            Spacer()
                            
                            if selectedChain == chain {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.body)
                                    .foregroundStyle(chipGoldGradient)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    
                    if index < chainRegistry.supportedChains.count - 1 {
                        Rectangle()
                            .fill(DS.Adaptive.divider)
                            .frame(height: 1)
                            .padding(.leading, 66)
                    }
                }
            }
            .background(premiumCardBackground)
        }
    }
    
    private var walletDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Wallet Details")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(DS.Adaptive.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 4)
            
            VStack(spacing: 16) {
                // Address field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Wallet Address")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    TextField("0x... or SOL address", text: $walletAddress)
                        .font(.subheadline)
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(DS.Adaptive.cardBackgroundElevated)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(DS.Adaptive.stroke, lineWidth: 1)
                        )
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .monospaced()
                }
                
                // Nickname field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nickname (Optional)")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    TextField("My Trading Wallet", text: $walletName)
                        .font(.subheadline)
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(DS.Adaptive.cardBackgroundElevated)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(DS.Adaptive.stroke, lineWidth: 1)
                        )
                }
            }
            .padding(16)
            .background(premiumCardBackground)
            
            if let chain = selectedChain {
                Text("Enter your \(chain.displayName) wallet address. We only track balances - no transactions are made.")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .padding(.horizontal, 4)
            }
        }
    }
    
    private var connectButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            connectWallet()
        } label: {
            HStack {
                if isConnecting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: colorScheme == .dark ? .black : .white))
                        .padding(.trailing, 8)
                }
                Text(isConnecting ? "Connecting..." : "Connect Wallet")
                    .font(.headline)
            }
            .foregroundColor(colorScheme == .dark ? .black : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                Group {
                    if selectedChain == nil || walletAddress.isEmpty || isConnecting {
                        DS.Adaptive.cardBackgroundElevated
                    } else {
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange]
                                : [.blue, .blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(selectedChain == nil || walletAddress.isEmpty || isConnecting)
        .opacity((selectedChain == nil || walletAddress.isEmpty) ? 0.6 : 1.0)
    }
    
    // MARK: - Premium Card Background
    
    private var premiumCardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
            
            // Top highlight
            LinearGradient(
                colors: [Color.white.opacity(colorScheme == .dark ? 0.06 : 0.5), Color.clear],
                startPoint: .top,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        }
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
    }
    
    // MARK: - Actions
    
    private func connectWallet() {
        guard let chain = selectedChain else { return }
        
        isConnecting = true
        errorMessage = nil
        
        Task {
            let normalizedAddress = walletAddress.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Validate address format based on chain
            guard isValidAddress(normalizedAddress, for: chain) else {
                await MainActor.run {
                    errorMessage = "Invalid \(chain.displayName) address format"
                    isConnecting = false
                }
                return
            }
            
            // Connect the wallet
            await multiChainVM.connectWallet(
                address: normalizedAddress,
                chainId: chain.rawValue,
                name: walletName.isEmpty ? nil : walletName
            )
            
            await MainActor.run {
                isConnecting = false
                showingAddWallet = false
                resetForm()
            }
        }
    }
    
    private func resetForm() {
        walletAddress = ""
        walletName = ""
        selectedChain = nil
        errorMessage = nil
    }
    
    // MARK: - Helpers
    
    private func shortenAddress(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = CurrencyManager.currencyCode
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }
    
    private func isValidAddress(_ address: String, for chain: Chain) -> Bool {
        // Basic validation
        if address.isEmpty { return false }
        
        if chain.isEVM {
            // EVM addresses start with 0x and are 42 characters
            return address.hasPrefix("0x") && address.count == 42
        }
        
        switch chain {
        case .solana:
            // Solana addresses are base58 encoded, 32-44 characters
            return address.count >= 32 && address.count <= 44
        case .bitcoin:
            // Bitcoin addresses vary, typically 25-35 characters
            return address.count >= 25 && address.count <= 35
        default:
            return address.count > 10
        }
    }
}

// MARK: - Premium Chain Icon Component

/// A premium blockchain icon component with brand-accurate representations
struct PremiumChainIcon: View {
    let chain: Chain?
    var size: CGFloat = 40
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            // Background with gradient
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            brandColor.opacity(colorScheme == .dark ? 0.35 : 0.25),
                            brandColor.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Border ring
            Circle()
                .stroke(brandColor.opacity(0.4), lineWidth: 1.5)
            
            // Chain-specific logo
            chainLogo
        }
        .frame(width: size, height: size)
    }
    
    private var brandColor: Color {
        chain?.brandColor ?? .gray
    }
    
    @ViewBuilder
    private var chainLogo: some View {
        if let chain = chain {
            switch chain {
            case .ethereum:
                // Ethereum diamond logo
                EthereumLogo(color: brandColor)
                    .frame(width: size * 0.5, height: size * 0.5)
                
            case .bitcoin:
                // Bitcoin B logo
                BitcoinLogo(color: brandColor)
                    .frame(width: size * 0.5, height: size * 0.5)
                
            case .solana:
                // Solana gradient logo
                SolanaLogo(color: brandColor)
                    .frame(width: size * 0.5, height: size * 0.5)
                
            case .avalanche:
                // Avalanche A logo
                AvalancheLogo(color: brandColor)
                    .frame(width: size * 0.5, height: size * 0.5)
                
            case .bsc:
                // BNB Chain logo
                BNBLogo(color: brandColor)
                    .frame(width: size * 0.5, height: size * 0.5)
                
            case .polygon:
                // Polygon logo
                PolygonLogo(color: brandColor)
                    .frame(width: size * 0.5, height: size * 0.5)
                
            case .arbitrum:
                // Arbitrum logo
                ArbitrumLogo(color: brandColor)
                    .frame(width: size * 0.5, height: size * 0.5)
                
            case .optimism:
                // Optimism logo
                OptimismLogo(color: brandColor)
                    .frame(width: size * 0.5, height: size * 0.5)
                
            case .base:
                // Base logo
                BaseLogo(color: brandColor)
                    .frame(width: size * 0.5, height: size * 0.5)
                
            case .fantom:
                // Fantom logo
                FantomLogo(color: brandColor)
                    .frame(width: size * 0.5, height: size * 0.5)
                
            case .zksync:
                // zkSync logo
                ZkSyncLogo(color: brandColor)
                    .frame(width: size * 0.5, height: size * 0.5)
                
            default:
                // Generic logo for new chains - use first letter of chain name
                let initial = String(chain.displayName.prefix(1))
                Text(initial)
                    .font(.system(size: size * 0.35, weight: .bold))
                    .foregroundColor(brandColor)
            }
        } else {
            // Unknown chain fallback
            Text("?")
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundColor(.gray)
        }
    }
}

// MARK: - Chain Logo Components

struct EthereumLogo: View {
    let color: Color
    
    var body: some View {
        GeometryReader { geo in
            Path { path in
                let w = geo.size.width
                let h = geo.size.height
                
                // Top point
                path.move(to: CGPoint(x: w * 0.5, y: 0))
                // Right side
                path.addLine(to: CGPoint(x: w, y: h * 0.55))
                path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.38))
                path.closeSubpath()
                
                // Left side
                path.move(to: CGPoint(x: w * 0.5, y: 0))
                path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.38))
                path.addLine(to: CGPoint(x: 0, y: h * 0.55))
                path.closeSubpath()
                
                // Bottom right
                path.move(to: CGPoint(x: w * 0.5, y: h * 0.45))
                path.addLine(to: CGPoint(x: w, y: h * 0.58))
                path.addLine(to: CGPoint(x: w * 0.5, y: h))
                path.closeSubpath()
                
                // Bottom left
                path.move(to: CGPoint(x: w * 0.5, y: h * 0.45))
                path.addLine(to: CGPoint(x: w * 0.5, y: h))
                path.addLine(to: CGPoint(x: 0, y: h * 0.58))
                path.closeSubpath()
            }
            .fill(color)
        }
    }
}

struct BitcoinLogo: View {
    let color: Color
    
    var body: some View {
        Text("₿")
            .font(.system(size: 100, weight: .bold, design: .rounded))
            .minimumScaleFactor(0.01)
            .foregroundColor(color)
    }
}

struct SolanaLogo: View {
    let color: Color
    
    var body: some View {
        VStack(spacing: 1) {
            ForEach(0..<3) { i in
                HStack(spacing: 0) {
                    if i % 2 == 0 {
                        Rectangle()
                            .fill(color)
                        Triangle()
                            .fill(color)
                            .rotationEffect(.degrees(i == 0 ? -90 : 90))
                    } else {
                        Triangle()
                            .fill(color)
                            .rotationEffect(.degrees(90))
                        Rectangle()
                            .fill(color)
                    }
                }
                .frame(height: 5)
            }
        }
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct AvalancheLogo: View {
    let color: Color
    
    var body: some View {
        GeometryReader { geo in
            Path { path in
                let w = geo.size.width
                let h = geo.size.height
                
                // Main A shape
                path.move(to: CGPoint(x: w * 0.5, y: 0))
                path.addLine(to: CGPoint(x: w, y: h))
                path.addLine(to: CGPoint(x: w * 0.7, y: h))
                path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.55))
                path.addLine(to: CGPoint(x: w * 0.3, y: h))
                path.addLine(to: CGPoint(x: 0, y: h))
                path.closeSubpath()
            }
            .fill(color)
        }
    }
}

struct BNBLogo: View {
    let color: Color
    
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let diamondSize = w * 0.3
            
            ZStack {
                // Center diamond
                Diamond()
                    .fill(color)
                    .frame(width: diamondSize, height: diamondSize)
                
                // Top diamond
                Diamond()
                    .fill(color)
                    .frame(width: diamondSize * 0.6, height: diamondSize * 0.6)
                    .offset(y: -h * 0.35)
                
                // Bottom diamond
                Diamond()
                    .fill(color)
                    .frame(width: diamondSize * 0.6, height: diamondSize * 0.6)
                    .offset(y: h * 0.35)
                
                // Left diamond
                Diamond()
                    .fill(color)
                    .frame(width: diamondSize * 0.6, height: diamondSize * 0.6)
                    .offset(x: -w * 0.35)
                
                // Right diamond
                Diamond()
                    .fill(color)
                    .frame(width: diamondSize * 0.6, height: diamondSize * 0.6)
                    .offset(x: w * 0.35)
            }
            .frame(width: w, height: h)
        }
    }
}

struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

struct PolygonLogo: View {
    let color: Color
    
    var body: some View {
        GeometryReader { geo in
            Path { path in
                let w = geo.size.width
                let h = geo.size.height
                
                // Main hexagon-ish shape
                path.move(to: CGPoint(x: w * 0.5, y: 0))
                path.addLine(to: CGPoint(x: w, y: h * 0.25))
                path.addLine(to: CGPoint(x: w, y: h * 0.75))
                path.addLine(to: CGPoint(x: w * 0.5, y: h))
                path.addLine(to: CGPoint(x: 0, y: h * 0.75))
                path.addLine(to: CGPoint(x: 0, y: h * 0.25))
                path.closeSubpath()
            }
            .fill(color)
        }
    }
}

struct ArbitrumLogo: View {
    let color: Color
    
    var body: some View {
        Text("A")
            .font(.system(size: 100, weight: .bold, design: .rounded))
            .minimumScaleFactor(0.01)
            .foregroundColor(color)
    }
}

struct OptimismLogo: View {
    let color: Color
    
    var body: some View {
        Circle()
            .fill(color)
            .overlay(
                Circle()
                    .fill(Color.white.opacity(0.3))
                    .scaleEffect(0.5)
                    .offset(x: -2, y: -2)
            )
    }
}

struct BaseLogo: View {
    let color: Color
    
    var body: some View {
        Circle()
            .fill(color)
            .overlay(
                Text("b")
                    .font(.system(size: 100, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.01)
                    .foregroundColor(.white)
                    .offset(x: 1)
            )
    }
}

struct FantomLogo: View {
    let color: Color
    
    var body: some View {
        Text("F")
            .font(.system(size: 100, weight: .bold, design: .rounded))
            .minimumScaleFactor(0.01)
            .foregroundColor(color)
    }
}

struct ZkSyncLogo: View {
    let color: Color
    
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            
            ZStack {
                // Z shape
                Path { path in
                    path.move(to: CGPoint(x: 0, y: h * 0.2))
                    path.addLine(to: CGPoint(x: w, y: h * 0.2))
                    path.addLine(to: CGPoint(x: w * 0.2, y: h * 0.8))
                    path.addLine(to: CGPoint(x: w, y: h * 0.8))
                }
                .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

// MARK: - Preview

#Preview {
    MultiChainWalletView()
}
