import SwiftUI

// MARK: - Brand Colors
private let accentGreen = Color(red: 0.2, green: 0.85, blue: 0.65)
private let accentBlue = Color(red: 0.3, green: 0.5, blue: 0.95)
private let accentPurple = Color(red: 0.65, green: 0.4, blue: 0.95)
private let accentOrange = Color(red: 0.95, green: 0.6, blue: 0.2)

struct PortfolioPaymentMethodsView: View {
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var appState: AppState
    
    // Stock feature toggle
    @AppStorage("showStocksInPortfolio") private var showStocksInPortfolio: Bool = false
    
    // Connected accounts manager
    @ObservedObject private var accountsManager = ConnectedAccountsManager.shared
    
    // Callback for when stocks are added (optional)
    var onStockAdded: ((Holding) -> Void)?
    
    // Navigation states
    @State private var showAllExchanges = false
    @State private var showOAuthExchanges = false
    @State private var showAPIKeyExchanges = false
    @State private var showWallets = false
    @State private var show3Commas = false
    @State private var showAddStockManually = false
    @State private var showAddCommodityManually = false
    @State private var showConnectBrokerage = false
    
    // For deletion/modification
    @State private var accountToRemove: ConnectedAccount?
    @State private var showRemoveConfirmation = false
    @State private var accountToMakeDefault: ConnectedAccount?
    @State private var showMakeDefaultConfirmation = false
    @State private var accountToRename: ConnectedAccount?
    @State private var renameText: String = ""
    @State private var showRenameSheet = false
    
    // Stats
    private var connectedCount: Int {
        accountsManager.accounts.count
    }
    
    private var lastSyncTime: String? {
        guard let lastSync = accountsManager.accounts.compactMap({ $0.lastSyncAt }).max() else {
            return nil
        }
        return timeAgo(lastSync)
    }
    
    var body: some View {
        ZStack {
            // Background - adaptive for light/dark mode
            DS.Adaptive.background
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // MARK: - Custom Top Bar (matching Settings page style)
                CSPageHeader(title: "Connections", leadingAction: {
                    presentationMode.wrappedValue.dismiss()
                })
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // MARK: - Header Section
                        headerSection
                        
                        // MARK: - Stats Bar (if accounts connected)
                        if connectedCount > 0 {
                            statsBar
                        }
                        
                        // MARK: - Connected Accounts (if any)
                        if !accountsManager.accounts.isEmpty {
                            connectedAccountsSection
                        }
                        
                        // MARK: - Connection Options Cards
                        connectionOptionsSection
                        
                        // MARK: - Security Footer
                        securityFooter
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.top, 20)
                }
                .scrollViewBackSwipeFix()
            }
            
        }
        .navigationDestination(isPresented: $showAllExchanges) {
            ExchangesView(filter: .all)
        }
        .navigationDestination(isPresented: $showOAuthExchanges) {
            ExchangesView(filter: .oauth)
        }
        .navigationDestination(isPresented: $showAPIKeyExchanges) {
            ExchangesView(filter: .apiKey)
        }
        .navigationDestination(isPresented: $showWallets) {
            ExchangesView(filter: .wallets)
        }
        .navigationDestination(isPresented: $show3Commas) {
            Link3CommasView()
        }
        .navigationDestination(isPresented: $showAddStockManually) {
            AddStockHoldingView { holding in
                BrokeragePortfolioDataService.shared.addManualHolding(holding)
                onStockAdded?(holding)
                if let ticker = holding.ticker {
                    Task { @MainActor in
                        LiveStockPriceManager.shared.addTickers([ticker], source: "portfolio")
                    }
                }
                showAddStockManually = false
            }
        }
        .navigationDestination(isPresented: $showAddCommodityManually) {
            AddCommodityView { holding in
                BrokeragePortfolioDataService.shared.addManualHolding(holding)
                onStockAdded?(holding)
                showAddCommodityManually = false
            }
        }
        .navigationDestination(isPresented: $showConnectBrokerage) {
            BrokerageConnectionView { holdings in
                for holding in holdings {
                    BrokeragePortfolioDataService.shared.addManualHolding(holding)
                }
                holdings.forEach { onStockAdded?($0) }
                let tickers = holdings.compactMap { $0.ticker }
                if !tickers.isEmpty {
                    Task { @MainActor in
                        LiveStockPriceManager.shared.addTickers(tickers, source: "portfolio")
                    }
                }
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .confirmationDialog(
            "Remove \(accountToRemove?.name ?? "this account")?",
            isPresented: $showRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let account = accountToRemove {
                    accountsManager.removeAccount(account)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will disconnect the account from your portfolio.")
        }
        .confirmationDialog(
            "Make \(accountToMakeDefault?.name ?? "this") default?",
            isPresented: $showMakeDefaultConfirmation,
            titleVisibility: .visible
        ) {
            Button("Set as Default") {
                if let account = accountToMakeDefault {
                    accountsManager.setAsDefault(account)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showRenameSheet) {
            RenameExchangeSheet(exchangeName: $renameText) {
                if let account = accountToRename {
                    accountsManager.renameAccount(account, newName: renameText)
                }
            }
        }
        // NAVIGATION: Enable native iOS pop gesture + custom edge swipe
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { presentationMode.wrappedValue.dismiss() })
        // Pop-to-root: Dismiss all nested navigation when Portfolio tab is tapped
        .onChange(of: appState.dismissPortfolioSubviews) { _, shouldDismiss in
            // Defer to avoid "Modifying state during view update"
            DispatchQueue.main.async {
                if shouldDismiss {
                    // Clear all navigation states
                    if showAllExchanges { showAllExchanges = false }
                    if showOAuthExchanges { showOAuthExchanges = false }
                    if showAPIKeyExchanges { showAPIKeyExchanges = false }
                    if showWallets { showWallets = false }
                    if show3Commas { show3Commas = false }
                    if showAddStockManually { showAddStockManually = false }
                    if showAddCommodityManually { showAddCommodityManually = false }
                    if showConnectBrokerage { showConnectBrokerage = false }
                    // Reset the trigger after handling
                    appState.dismissPortfolioSubviews = false
                }
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [accentGreen.opacity(0.3), accentBlue.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "link.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [accentGreen, accentBlue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            Text("Connect Your Portfolio")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Text("Link exchanges and wallets to track\nyour crypto in one place")
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .padding(.horizontal, 24)
    }
    
    // MARK: - Stats Bar
    
    private var statsBar: some View {
        HStack(spacing: 16) {
            // Connected accounts count
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("\(connectedCount) Connected")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(DS.Adaptive.textPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(DS.Adaptive.chipBackground)
            .cornerRadius(20)
            
            // Last sync time
            if let syncTime = lastSyncTime {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(DS.Adaptive.textSecondary)
                    Text("Synced \(syncTime)")
                        .font(.subheadline)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(DS.Adaptive.chipBackground)
                .cornerRadius(20)
            }
        }
    }
    
    // MARK: - Connected Accounts Section
    
    private var connectedAccountsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Connected Accounts")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(DS.Adaptive.textPrimary)
                .padding(.horizontal, 20)
            
            VStack(spacing: 8) {
                ForEach(accountsManager.accounts) { account in
                    ConnectedAccountRow(
                        account: account,
                        onRemove: {
                            accountToRemove = account
                            showRemoveConfirmation = true
                        },
                        onMakeDefault: {
                            accountToMakeDefault = account
                            showMakeDefaultConfirmation = true
                        },
                        onRename: {
                            accountToRename = account
                            renameText = account.name
                            showRenameSheet = true
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    // MARK: - Connection Options Section
    
    private var connectionOptionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Connection")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(DS.Adaptive.textPrimary)
                .padding(.horizontal, 20)
            
            VStack(spacing: 12) {
                // Quick Connect (OAuth) - Shows only OAuth exchanges
                ConnectionOptionCard(
                    icon: "bolt.fill",
                    iconColor: accentGreen,
                    title: "Quick Connect",
                    subtitle: "One-click login with Coinbase, Kraken, or Gemini",
                    buttonText: "Connect",
                    buttonColor: accentGreen
                ) {
                    showOAuthExchanges = true
                }
                
                // Exchange API Keys - Shows only API Key exchanges
                ConnectionOptionCard(
                    icon: "key.fill",
                    iconColor: accentOrange,
                    title: "Exchange API",
                    subtitle: "Connect Binance, KuCoin, Bybit with read-only API keys",
                    buttonText: "Add Keys",
                    buttonColor: accentOrange
                ) {
                    showAPIKeyExchanges = true
                }
                
                // Wallet Address Tracking - Shows only wallets
                ConnectionOptionCard(
                    icon: "wallet.pass.fill",
                    iconColor: accentPurple,
                    title: "Track Wallets",
                    subtitle: "ETH, BTC, SOL, Polygon, Arbitrum, Base, Avalanche, BNB",
                    buttonText: "Add Wallet",
                    buttonColor: accentPurple
                ) {
                    showWallets = true
                }
                
                // 3Commas (Advanced) - Only show for developers (trading feature)
                if SubscriptionManager.shared.isDeveloperMode {
                    ConnectionOptionCard(
                        icon: "gearshape.2.fill",
                        iconColor: Color.cyan,
                        title: "3Commas Integration",
                        subtitle: "For trading bots and advanced portfolio management",
                        buttonText: "Setup",
                        buttonColor: Color.cyan
                    ) {
                        show3Commas = true
                    }
                }
            }
            .padding(.horizontal, 16)
            
            // MARK: - Stocks & ETFs Section (only when enabled)
            if showStocksInPortfolio {
                stocksConnectionSection
            }
            
            // MARK: - Commodities Section (always visible)
            commoditiesSection
        }
    }
    
    // MARK: - Stocks Connection Section
    
    private var stocksConnectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header with beta badge
            HStack(spacing: 8) {
                Text("Stocks & ETFs")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text("BETA")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(accentBlue)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            
            VStack(spacing: 12) {
                // Add Stock Manually
                ConnectionOptionCard(
                    icon: "chart.line.uptrend.xyaxis",
                    iconColor: accentBlue,
                    title: "Add Stock Manually",
                    subtitle: "Search and add individual stocks or ETFs to track",
                    buttonText: "Add",
                    buttonColor: accentBlue
                ) {
                    showAddStockManually = true
                }
                
                // Connect Brokerage
                ConnectionOptionCard(
                    icon: "building.columns.fill",
                    iconColor: Color(red: 0.4, green: 0.7, blue: 0.4),
                    title: "Connect Brokerage",
                    subtitle: "Link Robinhood, Fidelity, or Schwab via Plaid",
                    buttonText: "Link",
                    buttonColor: Color(red: 0.4, green: 0.7, blue: 0.4)
                ) {
                    showConnectBrokerage = true
                }
            }
            .padding(.horizontal, 16)
            
            // Info note
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textTertiary)
                
                Text("Stock tracking is read-only. Trading is not supported.")
                    .font(.caption2)
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
        }
    }
    
    // MARK: - Commodities Section
    
    @ViewBuilder
    private var commoditiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack(spacing: 8) {
                Text("Commodities & Metals")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text("NEW")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.yellow)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            
            VStack(spacing: 12) {
                // Add Commodity Manually
                ConnectionOptionCard(
                    icon: "cube.fill",
                    iconColor: Color(red: 0.85, green: 0.65, blue: 0.13),
                    title: "Add Commodity",
                    subtitle: "Track gold, silver, oil and other commodities",
                    buttonText: "Add",
                    buttonColor: Color(red: 0.85, green: 0.65, blue: 0.13)
                ) {
                    showAddCommodityManually = true
                }
            }
            .padding(.horizontal, 16)
            
            // Info note
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textTertiary)
                
                Text("Track physical gold, silver, and other commodities in your portfolio.")
                    .font(.caption2)
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
        }
    }
    
    // MARK: - Security Footer
    
    private var securityFooter: some View {
        VStack(spacing: 16) {
            Divider()
                .background(DS.Adaptive.divider)
                .padding(.horizontal, 40)
            
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text("Your Security")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                VStack(spacing: 4) {
                    Text("API keys stored securely in device Keychain")
                    Text("Wallet tracking uses only public blockchain data")
                    Text("OAuth connections never share your password")
                }
                .font(.caption2)
                .foregroundColor(DS.Adaptive.textTertiary)
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, 8)
    }
    
    // MARK: - Helpers
    
    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}

// MARK: - Connection Option Card

struct ConnectionOptionCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let buttonText: String
    let buttonColor: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(iconColor)
                }
                
                // Text content
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
                
                // Arrow
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(buttonColor)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(DS.Adaptive.chipBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(DS.Adaptive.stroke, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Connected Account Row

struct ConnectedAccountRow: View {
    let account: ConnectedAccount
    let onRemove: () -> Void
    let onMakeDefault: () -> Void
    let onRename: () -> Void
    @State private var showActionMenu: Bool = false
    
    private var providerColor: Color {
        switch account.provider {
        case "oauth": return Color(red: 0.2, green: 0.85, blue: 0.65)
        case "direct": return Color(red: 0.95, green: 0.6, blue: 0.2)
        case "blockchain": return Color(red: 0.65, green: 0.4, blue: 0.95)
        default: return Color.cyan
        }
    }
    
    private var providerIcon: String {
        switch account.provider {
        case "oauth": return "bolt.fill"
        case "direct": return "key.fill"
        case "blockchain": return "wallet.pass.fill"
        default: return "link"
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Exchange/wallet logo
            ExchangeLogoView(name: account.name, size: 44)
            
            // Account info
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .lineLimit(1)
                
                HStack(spacing: 6) {
                    // Provider badge
                    Text(account.provider.capitalized)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(providerColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(providerColor.opacity(0.15))
                        .cornerRadius(4)
                    
                    if let lastSync = account.lastSyncAt {
                        Text("• \(timeAgo(lastSync))")
                            .font(.caption2)
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                }
            }
            
            Spacer()
            
            // Default badge
            if account.isDefault {
                Text("Default")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green)
                    .cornerRadius(6)
            }
            
            // Action menu button
            Button {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                showActionMenu = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showActionMenu, arrowEdge: .leading) {
                AccountActionMenuPopover(
                    isPresented: $showActionMenu,
                    isDefault: account.isDefault,
                    onMakeDefault: onMakeDefault,
                    onRename: onRename,
                    onRemove: onRemove
                )
                .presentationCompactAdaptation(.popover)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(DS.Adaptive.chipBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            account.isDefault ? Color.green.opacity(0.3) : DS.Adaptive.stroke,
                            lineWidth: 1
                        )
                )
        )
    }
    
    private func timeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        
        if interval < 60 {
            return "just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }
}

// MARK: - Rename Sheet

struct RenameExchangeSheet: View {
    @Binding var exchangeName: String
    var onSave: () -> Void
    
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationView {
            ZStack {
                DS.Adaptive.background.ignoresSafeArea()
                
                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Account Nickname")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textSecondary)
                        
                    TextField("Enter nickname", text: $exchangeName)
                            .padding()
                            .foregroundColor(DS.Adaptive.textPrimary)
                            .background(DS.Adaptive.chipBackground)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 20)
                    
                    HStack(spacing: 12) {
                        Button {
                            presentationMode.wrappedValue.dismiss()
                        } label: {
                            Text("Cancel")
                                .font(.headline)
                                .foregroundColor(DS.Adaptive.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(DS.Adaptive.chipBackground)
                                .cornerRadius(12)
                        }
                        
                        Button {
                            onSave()
                        presentationMode.wrappedValue.dismiss()
                        } label: {
                            Text("Save")
                                .font(.headline)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer()
                }
                .padding(.top, 20)
            }
            .navigationTitle("Rename Account")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Info Card (kept for backwards compatibility)

struct InfoCardView: View {
    let title: String
    let message: String
    
    var body: some View {
            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text(message)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
            }
            .padding(.vertical, 16)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DS.Adaptive.chipBackground)
        )
        .padding(.horizontal, 24)
    }
}

// MARK: - Account Action Menu Popover
private struct AccountActionMenuPopover: View {
    @Binding var isPresented: Bool
    let isDefault: Bool
    let onMakeDefault: () -> Void
    let onRename: () -> Void
    let onRemove: () -> Void
    
    var body: some View {
        VStack(spacing: 2) {
            if !isDefault {
                actionRow(title: "Set as Default", icon: "star.fill", action: onMakeDefault)
            }
            
            actionRow(title: "Rename", icon: "pencil", action: onRename)
            
            Rectangle()
                .fill(DS.Adaptive.divider)
                .frame(height: 0.5)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
            
            actionRow(title: "Remove", icon: "trash", isDestructive: true, action: onRemove)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            LinearGradient(colors: [DS.Adaptive.gradientHighlight, .clear], startPoint: .top, endPoint: .center)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 0.75)
                .allowsHitTesting(false)
        )
        .frame(minWidth: 160, maxWidth: 200)
    }
    
    @ViewBuilder
    private func actionRow(title: String, icon: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
            isPresented = false
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isDestructive ? Color.red : DS.Adaptive.textPrimary)
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isDestructive ? Color.red : DS.Adaptive.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
