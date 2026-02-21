//
//  HardwareWalletConnectionView.swift
//  CryptoSage
//
//  Device discovery and pairing view for hardware wallets.
//  Premium design with brand-specific logos and animations.
//

import SwiftUI

struct HardwareWalletConnectionView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var hwManager = HardwareWalletManager.shared
    
    @State private var selectedWalletType: HWWalletType?
    @State private var isConnecting = false
    @State private var showingSetup = false
    @State private var showingAccounts = false
    @State private var connectionError: String?
    @State private var appeared = false
    
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
        NavigationStack {
            ZStack {
                // Premium background
                FuturisticBackground()
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        headerSection
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 20)
                            .animation(.easeOut(duration: 0.4).delay(0.1), value: appeared)
                        
                        // Connected Wallets
                        if hwManager.hasConnectedWallet {
                            connectedWalletsSection
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 20)
                                .animation(.easeOut(duration: 0.4).delay(0.15), value: appeared)
                        }
                        
                        // Available Wallets
                        availableWalletsSection
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 20)
                            .animation(.easeOut(duration: 0.4).delay(0.2), value: appeared)
                        
                        // Accounts
                        if !hwManager.accounts.isEmpty {
                            accountsSection
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 20)
                                .animation(.easeOut(duration: 0.4).delay(0.25), value: appeared)
                        }
                        
                        // Help
                        helpSection
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 20)
                            .animation(.easeOut(duration: 0.4).delay(0.3), value: appeared)
                    }
                    .padding()
                    .padding(.bottom, 20)
                }
            }
            .navigationBarHidden(true)
            .enableInteractivePopGesture()
            .edgeSwipeToDismiss(onDismiss: { dismiss() })
            .safeAreaInset(edge: .top) {
                customHeader
            }
            .sheet(isPresented: $showingSetup) {
                if let type = selectedWalletType {
                    if type == .ledger {
                        LedgerSetupView()
                    } else {
                        TrezorSetupView()
                    }
                }
            }
            .sheet(isPresented: $showingAccounts) {
                HWAccountsListView()
            }
            .alert("Connection Error", isPresented: .constant(connectionError != nil)) {
                Button("OK") { connectionError = nil }
            } message: {
                Text(connectionError ?? "")
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) {
                    appeared = true
                }
            }
        }
    }
    
    // MARK: - Custom Header
    
    private var customHeader: some View {
        HStack(spacing: 0) {
            // Close button
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Text("Close")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(chipGoldGradient)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Close")
            
            Spacer()
            
            // Title
            Text("Hardware Wallets")
                .font(.headline)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Spacer()
            
            // Spacer for balance
            Color.clear
                .frame(width: 60)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(DS.Adaptive.background.opacity(0.95))
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            // Premium shield icon with gradient
            ZStack {
                // Outer glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.1), Color.clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 60
                        )
                    )
                    .frame(width: 120, height: 120)
                
                // Inner circle
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.2), Color.purple.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                // Shield icon
                Image(systemName: "shield.checkered")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 8) {
                Text("Secure Your Crypto")
                    .font(.title2.bold())
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text("Connect your hardware wallet for maximum security when signing transactions")
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .background(premiumCardBackground)
    }
    
    // MARK: - Connected Wallets Section
    
    private var connectedWalletsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Connected")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                Spacer()
                
                Button("Manage Accounts") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showingAccounts = true
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(chipGoldGradient)
            }
            .padding(.horizontal, 4)
            
            VStack(spacing: 0) {
                ForEach(Array(hwManager.connectedWalletTypes.enumerated()), id: \.element) { index, type in
                    connectedWalletRow(type: type)
                    
                    if index < hwManager.connectedWalletTypes.count - 1 {
                        Rectangle()
                            .fill(DS.Adaptive.divider)
                            .frame(height: 1)
                            .padding(.leading, 70)
                    }
                }
            }
            .background(premiumCardBackground)
        }
    }
    
    private func connectedWalletRow(type: HWWalletType) -> some View {
        HStack(spacing: 14) {
            // Brand-specific logo
            walletBrandIcon(type: type, isConnected: true)
                .frame(width: 52, height: 52)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(type.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text("\(hwManager.accounts(for: type).count) accounts linked")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            
            Spacer()
            
            // Connection status badge
            HStack(spacing: 5) {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text("Connected")
                    .font(.caption.weight(.medium))
                    .foregroundColor(.green)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.green.opacity(0.15))
            .clipShape(Capsule())
            
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Task {
                    await hwManager.disconnect(type: type)
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
        }
        .padding(16)
    }
    
    // MARK: - Available Wallets Section
    
    private var availableWalletsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connect Wallet")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(DS.Adaptive.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 4)
            
            VStack(spacing: 12) {
                ForEach(HWWalletType.allCases, id: \.self) { type in
                    if !hwManager.isConnected(type) {
                        walletOptionRow(type: type)
                    }
                }
            }
        }
    }
    
    private func walletOptionRow(type: HWWalletType) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedWalletType = type
            showingSetup = true
        } label: {
            HStack(spacing: 14) {
                // Brand-specific logo
                walletBrandIcon(type: type, isConnected: false)
                    .frame(width: 52, height: 52)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(type.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Text(type.connectionMethod.displayName)
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                Spacer()
                
                // Connection type badge
                HStack(spacing: 4) {
                    Image(systemName: connectionIcon(for: type))
                        .font(.caption2)
                    Text(connectionLabel(for: type))
                        .font(.caption2.weight(.medium))
                }
                .foregroundColor(type == .ledger ? .blue : .green)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background((type == .ledger ? Color.blue : Color.green).opacity(0.12))
                .clipShape(Capsule())
                
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .padding(16)
            .background(premiumCardBackground)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Wallet Brand Icon
    
    private func walletBrandIcon(type: HWWalletType, isConnected: Bool) -> some View {
        ZStack {
            // Background with brand color
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: type == .ledger
                            ? [Color.blue.opacity(colorScheme == .dark ? 0.3 : 0.2), Color.blue.opacity(0.1)]
                            : [Color.green.opacity(colorScheme == .dark ? 0.3 : 0.2), Color.green.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            // Border
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    (type == .ledger ? Color.blue : Color.green).opacity(isConnected ? 0.5 : 0.3),
                    lineWidth: isConnected ? 2 : 1
                )
            
            // Brand logo representation
            if type == .ledger {
                // Ledger logo representation
                VStack(spacing: 2) {
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.blue.opacity(0.6))
                            .frame(width: 8, height: 8)
                    }
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.blue.opacity(0.6))
                            .frame(width: 8, height: 8)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.blue)
                            .frame(width: 8, height: 8)
                    }
                }
            } else {
                // Trezor logo representation - stylized T
                ZStack {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.green)
                        .frame(width: 20, height: 6)
                        .offset(y: -6)
                    
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.green)
                        .frame(width: 6, height: 18)
                        .offset(y: 3)
                }
            }
        }
    }
    
    private func connectionIcon(for type: HWWalletType) -> String {
        switch type.connectionMethod {
        case .bluetooth: return "antenna.radiowaves.left.and.right"
        case .usb: return "cable.connector"
        case .bridge: return "network"
        }
    }
    
    private func connectionLabel(for type: HWWalletType) -> String {
        switch type.connectionMethod {
        case .bluetooth: return "Bluetooth"
        case .usb: return "USB"
        case .bridge: return "Trezor Bridge"
        }
    }
    
    // MARK: - Accounts Section
    
    private var accountsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Accounts")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.5)
                
                Spacer()
                
                Button("View All") {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showingAccounts = true
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(chipGoldGradient)
            }
            .padding(.horizontal, 4)
            
            VStack(spacing: 0) {
                ForEach(Array(hwManager.accounts.prefix(3).enumerated()), id: \.element.id) { index, account in
                    accountRow(account)
                    
                    if index < min(2, hwManager.accounts.count - 1) {
                        Rectangle()
                            .fill(DS.Adaptive.divider)
                            .frame(height: 1)
                            .padding(.leading, 52)
                    }
                }
                
                if hwManager.accounts.count > 3 {
                    HStack {
                        Spacer()
                        Text("+\(hwManager.accounts.count - 3) more accounts")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Spacer()
                    }
                    .padding(.vertical, 12)
                }
            }
            .background(premiumCardBackground)
        }
    }
    
    private func accountRow(_ account: HWAccount) -> some View {
        HStack(spacing: 12) {
            // Chain icon
            ZStack {
                Circle()
                    .fill(account.chain.brandColor.opacity(colorScheme == .dark ? 0.25 : 0.15))
                    .frame(width: 40, height: 40)
                
                Circle()
                    .stroke(account.chain.brandColor.opacity(0.3), lineWidth: 1)
                    .frame(width: 40, height: 40)
                
                Text(account.chain.nativeSymbol.prefix(1))
                    .font(.subheadline.bold())
                    .foregroundColor(account.chain.brandColor)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(account.displayName)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text(account.shortAddress)
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .monospaced()
            }
            
            Spacer()
            
            Text(account.chain.displayName)
                .font(.caption.weight(.medium))
                .foregroundColor(account.chain.brandColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(account.chain.brandColor.opacity(0.12))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
    
    // MARK: - Help Section
    
    private var helpSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Need Help?")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(DS.Adaptive.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 4)
            
            VStack(spacing: 0) {
                helpRow(
                    icon: "questionmark.circle.fill",
                    iconColor: .blue,
                    title: "How to connect Ledger",
                    subtitle: "Step-by-step guide"
                )
                
                Rectangle()
                    .fill(DS.Adaptive.divider)
                    .frame(height: 1)
                    .padding(.leading, 52)
                
                helpRow(
                    icon: "exclamationmark.triangle.fill",
                    iconColor: .orange,
                    title: "Troubleshooting",
                    subtitle: "Common issues and fixes"
                )
                
                Rectangle()
                    .fill(DS.Adaptive.divider)
                    .frame(height: 1)
                    .padding(.leading, 52)
                
                helpRow(
                    icon: "lock.shield.fill",
                    iconColor: .green,
                    title: "Security Best Practices",
                    subtitle: "Keep your crypto safe"
                )
            }
            .background(premiumCardBackground)
        }
    }
    
    private func helpRow(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // TODO: Navigate to help content
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(colorScheme == .dark ? 0.2 : 0.12))
                        .frame(width: 40, height: 40)
                    
                    Image(systemName: icon)
                        .font(.body)
                        .foregroundColor(iconColor)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
}

#Preview {
    HardwareWalletConnectionView()
}
