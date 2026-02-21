//
//  WatchedWalletsView.swift
//  CryptoSage
//
//  View for managing watched whale wallets.
//

import SwiftUI

struct WatchedWalletsView: View {
    @ObservedObject var viewModel: WhaleTrackingViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showAddWallet: Bool = false
    @State private var selectedWallet: WatchedWallet?
    
    var body: some View {
        NavigationStack {
            ZStack {
                DS.Adaptive.background.ignoresSafeArea()
                
                if viewModel.watchedWallets.isEmpty {
                    emptyState
                } else {
                    walletsList
                }
            }
            .navigationTitle("Watched Wallets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { dismiss() } label: {
                        Text("Done")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(BrandColors.goldBase)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddWallet = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(BrandColors.goldBase)
                    }
                }
            }
            .sheet(isPresented: $showAddWallet) {
                AddWatchedWalletView(viewModel: viewModel)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
            .enableInteractivePopGesture()
            .edgeSwipeToDismiss(onDismiss: { dismiss() })
        }
    }
    
    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Main empty state
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue.opacity(0.2), Color.cyan.opacity(0.1)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "eye.slash")
                            .font(.system(size: 36, weight: .light))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .cyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    }
                    
                    Text("No Watched Wallets")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(DS.Adaptive.textPrimary)
                    
                    Text("Track specific whale wallets to monitor their activity and get notified when they make large movements.")
                        .font(.system(size: 14))
                        .foregroundStyle(DS.Adaptive.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .padding(.top, 40)
                
                // Add wallet button
                Button {
                    let impactLight = UIImpactFeedbackGenerator(style: .light)
                    impactLight.impactOccurred()
                    showAddWallet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                            .symbolRenderingMode(.hierarchical)
                        Text("Add Custom Wallet")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color.blue.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
                
                // Divider
                HStack {
                    Rectangle()
                        .fill(DS.Adaptive.divider)
                        .frame(height: 1)
                    Text("or quick add")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    Rectangle()
                        .fill(DS.Adaptive.divider)
                        .frame(height: 1)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 8)
                
                // Popular wallets suggestions
                VStack(alignment: .leading, spacing: 12) {
                    Text("Popular Wallets to Watch")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.Adaptive.textSecondary)
                        .padding(.horizontal, 4)
                    
                    ForEach(PopularWalletsToWatch.wallets) { wallet in
                        let isAlreadyWatched = viewModel.watchedWallets.contains {
                            $0.address.lowercased() == wallet.address.lowercased()
                        }
                        PopularWalletSuggestionRow(wallet: wallet, onAdd: {
                            WhaleTrackingService.shared.addWatchedWallet(wallet)
                        }, isAlreadyWatched: isAlreadyWatched)
                        .opacity(isAlreadyWatched ? 0.75 : 1.0)
                    }
                }
                .padding(.horizontal)
                
                // Why watch wallets?
                VStack(alignment: .leading, spacing: 12) {
                    Text("Why Watch Wallets?")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.Adaptive.textSecondary)
                    
                    whyWatchRow(icon: "bell.badge.fill", title: "Get Alerts", description: "Instant notifications when watched wallets move crypto")
                    whyWatchRow(icon: "chart.line.uptrend.xyaxis", title: "Track Smart Money", description: "Follow profitable traders and institutional wallets")
                    whyWatchRow(icon: "building.columns", title: "Exchange Flows", description: "Monitor major exchange hot/cold wallet movements")
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(DS.Adaptive.chipBackground)
                )
                .padding(.horizontal)
                .padding(.top, 8)
            }
            .padding(.bottom, 32)
        }
    }
    
    private func whyWatchRow(icon: String, title: String, description: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.blue)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Adaptive.textPrimary)
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Adaptive.textTertiary)
            }
        }
    }
    
    private var walletsList: some View {
        List {
            ForEach(viewModel.watchedWallets) { wallet in
                Button {
                    selectedWallet = wallet
                } label: {
                    WatchedWalletRow(wallet: wallet)
                }
                .buttonStyle(.plain)
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let wallet = viewModel.watchedWallets[index]
                    viewModel.removeWatchedWallet(id: wallet.id)
                }
            }
            
            // Add more section
            Section {
                Button {
                    showAddWallet = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.blue)
                        Text("Add Another Wallet")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .sheet(item: $selectedWallet) { wallet in
            WalletDetailView(wallet: wallet)
        }
    }
}

// MARK: - Popular Wallet Suggestion Row

struct PopularWalletSuggestionRow: View {
    let wallet: WatchedWallet
    let onAdd: () -> Void
    var isAlreadyWatched: Bool = false
    @State private var isAdded: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            // Blockchain coin logo
            CoinImageView(symbol: wallet.blockchain.symbol, url: nil, size: 36)
            
            // Details
            VStack(alignment: .leading, spacing: 2) {
                Text(wallet.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Adaptive.textPrimary)
                
                Text(wallet.shortAddress)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(DS.Adaptive.textTertiary)
            }
            
            Spacer()
            
            // Add button
            Button {
                guard !isAlreadyWatched else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isAdded = true
                }
                onAdd()
            } label: {
                if isAlreadyWatched || isAdded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.green)
                } else {
                    Text("Add")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.blue.opacity(0.15))
                        )
                }
            }
            .disabled(isAdded || isAlreadyWatched)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
    }
}

// MARK: - Watched Wallet Row

struct WatchedWalletRow: View {
    let wallet: WatchedWallet
    
    var body: some View {
        HStack(spacing: 12) {
            // Blockchain coin logo
            CoinImageView(symbol: wallet.blockchain.symbol, url: nil, size: 40)
            
            // Details
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(wallet.label)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.Adaptive.textPrimary)
                    
                    // Known wallet badge
                    if KnownWhaleLabels.label(for: wallet.address) != nil {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(BrandColors.goldBase)
                    }
                }
                
                Text(wallet.shortAddress)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(DS.Adaptive.textSecondary)
                
                if let lastActivity = wallet.lastActivity {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 5, height: 5)
                        Text("Active \(WhaleRelativeTimeFormatter.format(lastActivity))")
                            .font(.system(size: 10))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                    }
                }
            }
            
            Spacer()
            
            // Notification indicator and min amount
            VStack(alignment: .trailing, spacing: 4) {
                if wallet.notifyOnActivity {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(BrandColors.goldBase)
                }
                
                Text(">\(formatShort(wallet.minTransactionAmount))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DS.Adaptive.textTertiary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatShort(_ value: Double) -> String {
        if value >= 1_000_000 {
            return String(format: "$%.0fM", value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "$%.0fK", value / 1_000)
        }
        return String(format: "$%.0f", value)
    }
}

// MARK: - Add Watched Wallet View

struct AddWatchedWalletView: View {
    @ObservedObject var viewModel: WhaleTrackingViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var address: String = ""
    @State private var label: String = ""
    @State private var selectedBlockchain: WhaleBlockchain = .ethereum
    @State private var notifyOnActivity: Bool = true
    @State private var minAmountText: String = "100000"
    @State private var showSuggestions: Bool = false
    @State private var hasAppeared: Bool = false
    
    private var isFormValid: Bool {
        !address.isEmpty && !label.isEmpty
    }
    
    // Filtered suggestions based on current input
    private var filteredSuggestions: [(String, String)] {
        guard !address.isEmpty || !label.isEmpty else { return [] }
        
        return Array(KnownWhaleLabels.labels)
            .filter { addr, walletLabel in
                addr.lowercased().contains(address.lowercased()) ||
                walletLabel.lowercased().contains(label.lowercased()) ||
                walletLabel.lowercased().contains(address.lowercased())
            }
            .prefix(5)
            .map { ($0.key, $0.value) }
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Wallet Address", text: $address)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: address) { _, newValue in
                            guard hasAppeared else { return }
                            // Auto-detect blockchain
                            if let chain = KnownWhaleLabels.inferBlockchain(from: newValue) {
                                selectedBlockchain = chain
                            }
                            // Auto-fill label if known
                            if let knownLabel = KnownWhaleLabels.label(for: newValue), label.isEmpty {
                                label = knownLabel
                            }
                        }
                    
                    TextField("Label (e.g., Binance Cold)", text: $label)
                    
                    // Suggestions
                    if !filteredSuggestions.isEmpty && hasAppeared {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Suggestions")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(DS.Adaptive.textTertiary)
                            
                            ForEach(filteredSuggestions, id: \.0) { addr, walletLabel in
                                Button {
                                    address = addr
                                    label = walletLabel
                                    if let chain = KnownWhaleLabels.inferBlockchain(from: addr) {
                                        selectedBlockchain = chain
                                    }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(walletLabel)
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundStyle(DS.Adaptive.textPrimary)
                                            Text(addr.prefix(16) + "..." + addr.suffix(4))
                                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                                .foregroundStyle(DS.Adaptive.textTertiary)
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.up.left")
                                            .font(.system(size: 10))
                                            .foregroundStyle(DS.Adaptive.textTertiary)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Wallet Details")
                } footer: {
                    Text("Enter a wallet address or start typing to see suggestions from known whale wallets.")
                }
                
                Section("Blockchain") {
                    Picker("Network", selection: $selectedBlockchain) {
                        ForEach(WhaleBlockchain.allCases, id: \.rawValue) { chain in
                            Label(chain.rawValue, systemImage: chain.icon)
                                .tag(chain)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                Section {
                    Toggle("Notify on Activity", isOn: $notifyOnActivity)
                    
                    if notifyOnActivity {
                        HStack {
                            Text("Min Amount")
                            Spacer()
                            TextField("100000", text: $minAmountText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 120)
                                .onChange(of: minAmountText) { _, newValue in
                                    minAmountText = String(newValue.filter(\.isNumber).prefix(12))
                                }
                        }
                        
                        // Quick presets
                        HStack(spacing: 8) {
                            ForEach(["100K", "500K", "1M"], id: \.self) { preset in
                                let presetVal = presetValueForNotif(preset)
                                let isSelected = Double(minAmountText) == presetVal
                                Button {
                                    let impactLight = UIImpactFeedbackGenerator(style: .light)
                                    impactLight.impactOccurred()
                                    minAmountText = String(Int(presetVal))
                                } label: {
                                    Text(preset)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(isSelected ? .white : DS.Adaptive.textSecondary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(
                                            Capsule()
                                                .fill(isSelected ? Color.blue : DS.Adaptive.chipBackground)
                                        )
                                        .overlay(
                                            Capsule()
                                                .stroke(isSelected ? Color.clear : DS.Adaptive.stroke, lineWidth: 0.5)
                                        )
                                }
                                .buttonStyle(.plain)
                                .animation(.easeInOut(duration: 0.15), value: isSelected)
                            }
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("You'll receive a notification when this wallet moves more than the minimum amount.")
                }
                
                Section {
                    // Quick add known wallets
                    DisclosureGroup("Quick Add Known Wallets", isExpanded: $showSuggestions) {
                        ForEach(Array(KnownWhaleLabels.labels.prefix(8)), id: \.key) { addr, walletLabel in
                            Button {
                                address = addr
                                label = walletLabel
                                if let chain = KnownWhaleLabels.inferBlockchain(from: addr) {
                                    selectedBlockchain = chain
                                }
                            } label: {
                                HStack {
                                    if let chain = KnownWhaleLabels.inferBlockchain(from: addr) {
                                        Image(systemName: chain.icon)
                                            .font(.system(size: 12))
                                            .foregroundStyle(chain.color)
                                            .frame(width: 20)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(walletLabel)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(DS.Adaptive.textPrimary)
                                        Text(addr.prefix(12) + "..." + addr.suffix(4))
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundStyle(DS.Adaptive.textTertiary)
                                    }
                                    
                                    Spacer()
                                    
                                    if address == addr {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.green)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.gray)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        addWallet()
                    } label: {
                        Text("Add")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(isFormValid ? BrandColors.goldBase : DS.Adaptive.textTertiary)
                    }
                    .disabled(!isFormValid)
                }
            }
            .onAppear {
                // Delay to prevent immediate dismissal from viewModel changes
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    hasAppeared = true
                }
            }
        }
        .interactiveDismissDisabled(false)
    }
    
    private func addWallet() {
        let minAmount = Double(minAmountText) ?? 100_000
        let wallet = WatchedWallet(
            address: address,
            label: label,
            blockchain: selectedBlockchain,
            notifyOnActivity: notifyOnActivity,
            minTransactionAmount: minAmount
        )
        WhaleTrackingService.shared.addWatchedWallet(wallet)
        dismiss()
    }
    
    private func presetValueForNotif(_ preset: String) -> Double {
        switch preset {
        case "100K": return 100_000
        case "500K": return 500_000
        case "1M": return 1_000_000
        default: return 100_000
        }
    }
}

#Preview {
    WatchedWalletsView(viewModel: WhaleTrackingViewModel())
        .preferredColorScheme(.dark)
}
