//
//  BrokerageConnectionView.swift
//  CryptoSage
//
//  Created by CryptoSage on 1/19/26.
//  View for connecting brokerage accounts via Plaid.
//

import SwiftUI

struct BrokerageConnectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var connectedAccounts: [PlaidAccount] = []
    @State private var isLoading = false
    @State private var showingPlaidLink = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var selectedBrokerage: SupportedBrokerage?
    @State private var showSetupInstructions = false
    
    private var isDark: Bool { colorScheme == .dark }
    
    // Callback when holdings are synced
    var onHoldingsSync: (([Holding]) -> Void)?
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                (isDark ? Color.black : Color(UIColor.systemGroupedBackground))
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        headerSection
                        
                        // Connected Accounts
                        if !connectedAccounts.isEmpty {
                            connectedAccountsSection
                        }
                        
                        // Add Brokerage Section
                        addBrokerageSection
                        
                        // Disclaimer
                        disclaimerSection
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal)
                    .padding(.top, 16)
                }
                
                if isLoading {
                    loadingOverlay
                }
            }
            .navigationTitle("Brokerages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(isDark ? Color.black : Color(UIColor.systemGroupedBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(isDark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Text("Done")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(DS.Adaptive.gold)
                    }
                }
            }
            .alert("Connection Failed", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Unable to connect. Please try again.")
            }
            .sheet(isPresented: $showSetupInstructions) {
                PlaidSetupInstructionsView()
            }
            .task {
                await loadConnectedAccounts()
            }
            .enableInteractivePopGesture()
            .edgeSwipeToDismiss(onDismiss: { dismiss() })
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.2), Color.blue.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            Text("Connect Your Brokerages")
                .font(.title2.weight(.bold))
                .foregroundStyle(isDark ? .white : .primary)
            
            Text("Link your investment accounts to track stocks and ETFs alongside your crypto portfolio. Read-only access - we never trade on your behalf.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // Coming soon badge
            HStack(spacing: 6) {
                Image(systemName: "clock.badge.checkmark")
                    .font(.system(size: 11, weight: .semibold))
                Text("Auto-sync coming soon — add stocks manually for now")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.orange)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.orange.opacity(0.12))
            )
        }
        .padding(.vertical, 16)
    }
    
    // MARK: - Connected Accounts Section
    
    private var connectedAccountsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Connected Accounts")
                    .font(.headline)
                    .foregroundStyle(isDark ? .white : .primary)
                
                Spacer()
                
                Text("\(connectedAccounts.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green)
                    .clipShape(Capsule())
            }
            
            ForEach(connectedAccounts) { account in
                connectedAccountRow(account)
            }
        }
    }
    
    private func connectedAccountRow(_ account: PlaidAccount) -> some View {
        HStack(spacing: 12) {
            // Institution icon
            Image(systemName: "building.columns.fill")
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 44, height: 44)
                .background(Color.blue.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(account.institutionName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isDark ? .white : .primary)
                
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    
                    Text("Connected")
                        .font(.caption)
                        .foregroundStyle(.green)
                    
                    if let lastSync = account.lastSyncedAt {
                        Text("• Last synced \(lastSync.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Menu {
                Button {
                    Task { await syncAccount(account) }
                } label: {
                    Label("Sync Now", systemImage: "arrow.clockwise")
                }
                
                Button(role: .destructive) {
                    Task { await removeAccount(account) }
                } label: {
                    Label("Disconnect", systemImage: "xmark.circle")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isDark ? Color.white.opacity(0.08) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Add Brokerage Section
    
    private var addBrokerageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Popular Brokerages")
                .font(.headline)
                .foregroundStyle(isDark ? .white : .primary)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(SupportedBrokerage.popular) { brokerage in
                    brokerageButton(brokerage)
                }
            }
            
            // Connect other
            Button {
                checkPlaidAndConnect(nil)
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                    Text("Connect Other Brokerage")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(.blue)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.blue.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
            }
        }
    }
    
    private func brokerageButton(_ brokerage: SupportedBrokerage) -> some View {
        Button {
            checkPlaidAndConnect(brokerage)
        } label: {
            VStack(spacing: 10) {
                // Brokerage icon with distinctive styling
                BrokerageLogoView(brokerage: brokerage, size: 44)
                
                Text(brokerage.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isDark ? .white : .primary)
                    .lineLimit(1)
                
                if let notes = brokerage.notes {
                    Text(notes)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isDark ? Color.white.opacity(0.06) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Disclaimer Section
    
    private var disclaimerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.green)
                Text("Your Data is Secure")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isDark ? .white : .primary)
            }
            
            Text("We use Plaid, a secure bank-grade connection service used by thousands of apps. We only request read-only access to view your holdings - we can never move money or execute trades.")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text("CryptoSage is for portfolio tracking only. This is not financial advice.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .italic()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.green.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Loading Overlay
    
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
                
                Text("Connecting...")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(DS.Adaptive.cardBackground)
            )
        }
    }
    
    // MARK: - Actions
    
    private func loadConnectedAccounts() async {
        do {
            connectedAccounts = try await PlaidService.shared.loadAccounts()
        } catch {
            #if DEBUG
            print("Failed to load accounts: \(error)")
            #endif
        }
    }
    
    private func checkPlaidAndConnect(_ brokerage: SupportedBrokerage?) {
        Task {
            let isConfigured = await PlaidService.shared.isConfigured
            
            if !isConfigured {
                // Show user-friendly "coming soon" instead of developer setup instructions
                await MainActor.run {
                    errorMessage = "Brokerage connections are coming soon! You can add stocks manually in the meantime by going to Portfolio > Add Stock."
                    showError = true
                }
            } else {
                selectedBrokerage = brokerage
                await startPlaidLink()
            }
        }
    }
    
    private func startPlaidLink() async {
        isLoading = true
        
        do {
            // Generate a unique user ID (in production, use actual user ID)
            let userId = UUID().uuidString
            
            // Create link token
            _ = try await PlaidService.shared.createLinkToken(userId: userId)
            
            // TODO: Integrate Plaid Link SDK for live brokerage connections
            // 1. Initialize Plaid Link SDK with the link token
            // 2. Present the Plaid Link UI
            // 3. Handle the success/failure callbacks
            
            await MainActor.run {
                isLoading = false
                errorMessage = "Brokerage connections are coming soon! You can add stocks manually in the meantime by going to Portfolio > Add Stock."
                showError = true
            }
            
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = "Brokerage connections are coming soon! You can add stocks manually in the meantime by going to Portfolio > Add Stock."
                showError = true
            }
        }
    }
    
    private func syncAccount(_ account: PlaidAccount) async {
        isLoading = true
        
        do {
            let holdings = try await PlaidService.shared.fetchHoldings(for: account)
            
            // Convert to portfolio holdings
            let portfolioHoldings = holdings.map { $0.toHolding(source: "plaid:\(account.institutionName)") }
            
            // Update last synced time
            var updatedAccount = account
            updatedAccount.lastSyncedAt = Date()
            try await PlaidService.shared.saveAccount(updatedAccount)
            
            await MainActor.run {
                isLoading = false
                // Update local state
                if let index = connectedAccounts.firstIndex(where: { $0.id == account.id }) {
                    connectedAccounts[index] = updatedAccount
                }
                // Notify parent
                onHoldingsSync?(portfolioHoldings)
            }
            
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
    
    private func removeAccount(_ account: PlaidAccount) async {
        do {
            try await PlaidService.shared.removeAccount(account)
            await MainActor.run {
                connectedAccounts.removeAll { $0.id == account.id }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }
}

// MARK: - Plaid Setup Instructions View

struct PlaidSetupInstructionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(spacing: 12) {
                        Image(systemName: "gear.badge.questionmark")
                            .font(.system(size: 48))
                            .foregroundStyle(.orange)
                        
                        Text("Setup Required")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(isDark ? .white : .primary)
                        
                        Text("Plaid needs to be configured to enable brokerage connections.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    
                    // Steps
                    VStack(alignment: .leading, spacing: 16) {
                        setupStep(number: 1, title: "Sign up for Plaid", description: "Create an account at plaid.com and get your API credentials (Client ID and Secret).")
                        
                        setupStep(number: 2, title: "Add the SDK", description: "In Xcode: File > Add Package Dependencies, then add:\nhttps://github.com/plaid/plaid-link-ios")
                        
                        setupStep(number: 3, title: "Configure Keys", description: "Set environment variables or add to APIConfig.swift:\n• PLAID_CLIENT_ID\n• PLAID_SECRET\n• PLAID_ENV")
                        
                        setupStep(number: 4, title: "Set Up Backend", description: "Plaid requires server-side token exchange for security. Set up a backend endpoint or use Plaid's Quickstart.")
                    }
                    
                    // Links
                    VStack(spacing: 12) {
                        Link(destination: URL(string: "https://plaid.com")!) {
                            linkButton(title: "Go to Plaid.com", icon: "arrow.up.right.square")
                        }
                        
                        Link(destination: URL(string: "https://github.com/plaid/plaid-link-ios")!) {
                            linkButton(title: "Plaid iOS SDK", icon: "chevron.left.forwardslash.chevron.right")
                        }
                        
                        Link(destination: URL(string: "https://plaid.com/docs/quickstart/")!) {
                            linkButton(title: "Plaid Quickstart Guide", icon: "book.fill")
                        }
                    }
                    .padding(.top, 8)
                    
                    // Cost note
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                        Text("Note: Plaid charges per connection (~$0.50-$1.50). Consider this in your pricing model.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.1))
                    )
                    
                    Spacer(minLength: 40)
                }
                .padding()
            }
            .background((isDark ? Color.black : Color(UIColor.systemGroupedBackground)).ignoresSafeArea())
            .navigationTitle("Setup Instructions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(isDark ? Color.black : Color(UIColor.systemGroupedBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(isDark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                        Text("Done")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(DS.Adaptive.gold)
                    }
                }
            }
        }
    }
    
    private func setupStep(number: Int, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.blue))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isDark ? .white : .primary)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func linkButton(title: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
            Text(title)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.blue)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.blue.opacity(0.1))
        )
    }
}

// MARK: - Brokerage Logo View

/// Displays a distinctive styled logo for each brokerage using their brand colors
/// Uses text initials with brand colors since we can't bundle real logos
private struct BrokerageLogoView: View {
    let brokerage: SupportedBrokerage
    let size: CGFloat
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var brandInfo: (color: Color, icon: String, initials: String) {
        switch brokerage.id {
        case "fidelity":
            return (Color(red: 0.30, green: 0.60, blue: 0.25), "building.columns.fill", "F")
        case "schwab":
            return (Color(red: 0.20, green: 0.50, blue: 0.80), "building.columns.fill", "CS")
        case "vanguard":
            return (Color(red: 0.55, green: 0.10, blue: 0.10), "chart.line.uptrend.xyaxis", "V")
        case "robinhood":
            return (Color(red: 0.0, green: 0.80, blue: 0.35), "leaf.fill", "R")
        case "td_ameritrade":
            return (Color(red: 0.20, green: 0.50, blue: 0.20), "chart.bar.fill", "TD")
        case "etrade":
            return (Color(red: 0.40, green: 0.20, blue: 0.60), "star.fill", "E*")
        case "merrill":
            return (Color(red: 0.0, green: 0.30, blue: 0.60), "m.circle.fill", "ME")
        case "interactive":
            return (Color(red: 0.80, green: 0.10, blue: 0.10), "globe", "IB")
        case "webull":
            return (Color(red: 0.0, green: 0.55, blue: 0.90), "w.circle.fill", "W")
        case "sofi":
            return (Color(red: 0.35, green: 0.90, blue: 0.80), "s.circle.fill", "S")
        default:
            return (Color.blue, "building.columns", "?")
        }
    }
    
    var body: some View {
        let info = brandInfo
        
        ZStack {
            // Brand-colored background circle
            Circle()
                .fill(
                    LinearGradient(
                        colors: [info.color.opacity(0.25), info.color.opacity(0.10)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Circle()
                        .stroke(info.color.opacity(0.3), lineWidth: 1.5)
                )
            
            // Icon or initials
            Image(systemName: info.icon)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundColor(info.color)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Preview

#Preview("Brokerage Connection") {
    BrokerageConnectionView()
}

#Preview("Setup Instructions") {
    PlaidSetupInstructionsView()
}
