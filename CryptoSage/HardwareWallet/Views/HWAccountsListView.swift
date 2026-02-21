//
//  HWAccountsListView.swift
//  CryptoSage
//
//  List view for managing hardware wallet accounts.
//

import SwiftUI

struct HWAccountsListView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var hwManager = HardwareWalletManager.shared
    
    @State private var selectedChain: Chain?
    @State private var selectedWalletType: HWWalletType?
    @State private var showingAddAccount = false
    @State private var accountToDelete: HWAccount?
    
    var filteredAccounts: [HWAccount] {
        var accounts = hwManager.accounts
        
        if let chain = selectedChain {
            accounts = accounts.filter { $0.chain == chain }
        }
        
        if let type = selectedWalletType {
            accounts = accounts.filter { $0.walletType == type }
        }
        
        return accounts.sorted { $0.chain.displayName < $1.chain.displayName }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Filters
                    filterSection
                    
                    // Accounts List
                    if filteredAccounts.isEmpty {
                        emptyState
                    } else {
                        accountsList
                    }
                }
                .padding()
            }
            .background(backgroundColor)
            .navigationTitle("Hardware Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Text("Close")
                            .foregroundStyle(DS.Adaptive.textSecondary)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddAccount = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(BrandColors.goldBase)
                    }
                }
            }
            .sheet(isPresented: $showingAddAccount) {
                HardwareWalletConnectionView()
            }
            .alert("Remove Account?", isPresented: .constant(accountToDelete != nil)) {
                Button("Cancel", role: .cancel) {
                    accountToDelete = nil
                }
                Button("Remove", role: .destructive) {
                    if let account = accountToDelete {
                        hwManager.removeAccount(account)
                        accountToDelete = nil
                    }
                }
            } message: {
                if let account = accountToDelete {
                    Text("This will remove \(account.shortAddress) from CryptoSage. Your funds are safe on your hardware wallet.")
                }
            }
        }
    }
    
    private var filterSection: some View {
        VStack(spacing: 12) {
            // Chain Filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(title: "All Chains", isSelected: selectedChain == nil) {
                        selectedChain = nil
                    }
                    
                    let chains = Set(hwManager.accounts.map { $0.chain })
                    ForEach(Array(chains).sorted { $0.displayName < $1.displayName }, id: \.self) { chain in
                        filterChip(
                            title: chain.displayName,
                            isSelected: selectedChain == chain,
                            color: chain.brandColor
                        ) {
                            selectedChain = chain
                        }
                    }
                }
            }
            
            // Wallet Type Filter
            if hwManager.connectedWalletTypes.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip(title: "All Wallets", isSelected: selectedWalletType == nil) {
                            selectedWalletType = nil
                        }
                        
                        ForEach(hwManager.connectedWalletTypes, id: \.self) { type in
                            filterChip(title: type.displayName, isSelected: selectedWalletType == type) {
                                selectedWalletType = type
                            }
                        }
                    }
                }
            }
        }
    }
    
    private func filterChip(title: String, isSelected: Bool, color: Color = .accentColor, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(isSelected ? color : Color.secondary.opacity(0.15))
                }
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "wallet.pass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            
            Text("No Accounts")
                .font(.headline)
            
            Text("Connect a hardware wallet to add accounts")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                showingAddAccount = true
            } label: {
                Label("Connect Wallet", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    private var accountsList: some View {
        VStack(spacing: 8) {
            ForEach(filteredAccounts) { account in
                AccountRow(account: account) {
                    accountToDelete = account
                }
            }
        }
    }
}

// MARK: - Account Row

struct AccountRow: View {
    let account: HWAccount
    let onDelete: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var showingDetails = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Chain Icon
                ZStack {
                    Circle()
                        .fill(account.chain.brandColor.opacity(0.2))
                        .frame(width: 44, height: 44)
                    
                    Text(account.chain.nativeSymbol.prefix(1))
                        .font(.headline.bold())
                        .foregroundStyle(account.chain.brandColor)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(account.displayName)
                            .font(.subheadline.weight(.semibold))
                        
                        HStack(spacing: 4) {
                            Image(systemName: account.walletType.iconName)
                                .font(.caption2)
                            Text(account.walletType.displayName)
                                .font(.caption2)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    
                    Text(account.shortAddress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button {
                    showingDetails.toggle()
                } label: {
                    Image(systemName: showingDetails ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            
            if showingDetails {
                Divider()
                    .padding(.horizontal)
                
                VStack(spacing: 8) {
                    detailRow(label: "Chain", value: account.chain.displayName)
                    detailRow(label: "Full Address", value: account.address, isCopyable: true)
                    detailRow(label: "Derivation Path", value: account.derivationPath)
                    detailRow(label: "Index", value: "\(account.index)")
                    
                    Divider()
                    
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Remove Account", systemImage: "trash")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(white: 0.1) : .white)
        }
    }
    
    private func detailRow(label: String, value: String, isCopyable: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            if isCopyable {
                Button {
                    // SECURITY: Auto-clear clipboard after 60s for wallet addresses
                    SecurityManager.shared.secureCopy(value)
                } label: {
                    HStack(spacing: 4) {
                        Text(value)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        Image(systemName: "doc.on.doc")
                            .font(.caption2)
                    }
                    .foregroundStyle(.primary)
                }
            } else {
                Text(value)
                    .font(.caption)
            }
        }
    }
}

// MARK: - HW Signing Sheet

struct HWSigningSheet: View {
    let request: HWSigningRequest
    let onApprove: () -> Void
    let onReject: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "signature")
                    .font(.system(size: 40))
                    .foregroundColor(.accentColor)
                
                Text(request.displayInfo.title)
                    .font(.title3.bold())
                
                if let subtitle = request.displayInfo.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Account Info
            HStack {
                Circle()
                    .fill(request.account.chain.brandColor.opacity(0.2))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Text(request.account.chain.nativeSymbol.prefix(1))
                            .font(.caption.bold())
                            .foregroundStyle(request.account.chain.brandColor)
                    }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(request.account.displayName)
                        .font(.subheadline.weight(.medium))
                    Text(request.account.shortAddress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 4) {
                    Image(systemName: request.account.walletType.iconName)
                    Text(request.account.walletType.displayName)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color(white: 0.1) : Color(white: 0.95))
            }
            
            // Details
            if !request.displayInfo.details.isEmpty {
                VStack(spacing: 8) {
                    ForEach(request.displayInfo.details, id: \.label) { detail in
                        HStack {
                            Text(detail.label)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(detail.value)
                                .font(.subheadline.weight(.medium))
                        }
                    }
                }
                .padding()
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(colorScheme == .dark ? Color(white: 0.1) : Color(white: 0.95))
                }
            }
            
            // Warning
            if let warning = request.displayInfo.warningMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(warning)
                        .font(.caption)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.orange.opacity(0.1))
                }
            }
            
            Spacer()
            
            // Instructions
            HStack {
                Image(systemName: "info.circle")
                    .foregroundStyle(.secondary)
                Text("Review and confirm on your hardware wallet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            // Buttons
            HStack(spacing: 12) {
                Button {
                    onReject()
                } label: {
                    Text("Reject")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.secondary.opacity(0.2))
                        .foregroundStyle(.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                Button {
                    onApprove()
                } label: {
                    Text("Confirm")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding()
    }
}

extension HWAccountsListView {
    var backgroundColor: Color {
        colorScheme == .dark ? Color(white: 0.05) : Color(white: 0.96)
    }
}

#Preview {
    HWAccountsListView()
}
