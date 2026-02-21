//
//  ConnectionHealthView.swift
//  CryptoSage
//
//  Dashboard showing the health and sync status of all connected accounts.
//

import SwiftUI
import Combine

// MARK: - Connection Health Status

enum ConnectionHealthStatus: String {
    case healthy = "Healthy"
    case syncing = "Syncing"
    case stale = "Stale"
    case error = "Error"
    case unknown = "Unknown"
    case noConnections = "No Connections"
    
    var color: Color {
        switch self {
        case .healthy: return .green
        case .syncing: return .blue
        case .stale: return .orange
        case .error: return .red
        case .unknown: return .gray
        case .noConnections: return .secondary
        }
    }
    
    var icon: String {
        switch self {
        case .healthy: return "checkmark.circle.fill"
        case .syncing: return "arrow.triangle.2.circlepath"
        case .stale: return "exclamationmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        case .noConnections: return "link.circle"
        }
    }
}

// MARK: - Account Health Model

struct AccountHealth: Identifiable {
    let id: String
    let name: String
    let type: String // exchange or wallet
    let provider: String
    var status: ConnectionHealthStatus
    var lastSync: Date?
    var errorMessage: String?
    var balanceCount: Int
    var totalValue: Double?
    
    var timeSinceSync: String {
        guard let lastSync = lastSync else { return "Never synced" }
        let interval = Date().timeIntervalSince(lastSync)
        
        if interval < 60 {
            return "Just now"
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
    
    init(from account: ConnectedAccount) {
        self.id = account.id
        self.name = account.name
        self.type = account.exchangeType
        self.provider = account.provider
        self.lastSync = account.lastSyncAt
        self.balanceCount = 0
        self.totalValue = nil
        self.errorMessage = nil
        
        // Determine status based on last sync
        if let lastSync = account.lastSyncAt {
            let interval = Date().timeIntervalSince(lastSync)
            if interval < 300 { // Less than 5 minutes
                self.status = .healthy
            } else if interval < 3600 { // Less than 1 hour
                self.status = .healthy
            } else if interval < 86400 { // Less than 24 hours
                self.status = .stale
            } else {
                self.status = .stale
            }
        } else {
            self.status = .unknown
        }
    }
}

// MARK: - Connection Health View Model

@MainActor
final class ConnectionHealthViewModel: ObservableObject {
    @Published var accountHealths: [AccountHealth] = []
    @Published var isRefreshing = false
    @Published var overallStatus: ConnectionHealthStatus = .unknown
    @Published var lastRefresh: Date?
    
    private let accountsManager = ConnectedAccountsManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        // Subscribe to account changes
        accountsManager.$accounts
            .receive(on: DispatchQueue.main)
            .sink { [weak self] accounts in
                self?.updateHealths(from: accounts)
            }
            .store(in: &cancellables)
    }
    
    func updateHealths(from accounts: [ConnectedAccount]) {
        accountHealths = accounts.map { AccountHealth(from: $0) }
        updateOverallStatus()
    }
    
    private func updateOverallStatus() {
        if accountHealths.isEmpty {
            overallStatus = .noConnections
        } else if accountHealths.contains(where: { $0.status == .error }) {
            overallStatus = .error
        } else if accountHealths.contains(where: { $0.status == .stale }) {
            overallStatus = .stale
        } else if accountHealths.contains(where: { $0.status == .syncing }) {
            overallStatus = .syncing
        } else if accountHealths.allSatisfy({ $0.status == .healthy }) {
            overallStatus = .healthy
        } else {
            overallStatus = .unknown
        }
    }
    
    func refreshAll() async {
        guard !isRefreshing else { return }
        
        isRefreshing = true
        
        // Set all to syncing
        for i in accountHealths.indices {
            accountHealths[i].status = .syncing
        }
        
        // Simulate refresh - in production this would call the actual sync
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        
        // Update last sync times
        for i in accountHealths.indices {
            accountHealths[i].lastSync = Date()
            accountHealths[i].status = .healthy
        }
        
        lastRefresh = Date()
        isRefreshing = false
        updateOverallStatus()
    }
    
    func refreshAccount(_ id: String) async {
        guard let index = accountHealths.firstIndex(where: { $0.id == id }) else { return }
        
        accountHealths[index].status = .syncing
        
        // Simulate refresh
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        
        accountHealths[index].lastSync = Date()
        accountHealths[index].status = .healthy
        updateOverallStatus()
    }
}

// MARK: - Connection Health View

struct ConnectionHealthView: View {
    @StateObject private var viewModel = ConnectionHealthViewModel()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        VStack(spacing: 0) {
            CSPageHeader(title: "Connections", leadingAction: { dismiss() })
            
            ScrollView {
                VStack(spacing: 16) {
                    // Overall Status Card
                    overallStatusCard
                    
                    // Quick Actions
                    if !viewModel.accountHealths.isEmpty {
                        quickActionsSection
                    }
                    
                    // Connected Accounts
                    if viewModel.accountHealths.isEmpty {
                        emptyStateView
                    } else {
                        accountsList
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .scrollViewBackSwipeFix()
            .refreshable {
                await viewModel.refreshAll()
            }
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
    }
    
    // MARK: - Overall Status Card
    
    private var overallStatusCard: some View {
        VStack(spacing: 14) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(viewModel.accountHealths.isEmpty
                              ? DS.Adaptive.textTertiary.opacity(0.12)
                              : Color.green.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: viewModel.overallStatus.icon)
                        .font(.system(size: 18))
                        .foregroundColor(viewModel.accountHealths.isEmpty
                                         ? DS.Adaptive.textTertiary
                                         : viewModel.overallStatus.color)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Status")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                    Text(viewModel.overallStatus.rawValue)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(viewModel.accountHealths.count)")
                        .font(.title2.weight(.bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    Text(viewModel.accountHealths.count == 1 ? "Connection" : "Connections")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
            
            if let lastRefresh = viewModel.lastRefresh {
                HStack {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                    Text("Last refreshed \(lastRefresh.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                }
                .foregroundColor(DS.Adaptive.textTertiary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(DS.Adaptive.stroke, lineWidth: 1)
                )
        )
    }
    
    // MARK: - Quick Actions
    
    private var quickActionsSection: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            Task { await viewModel.refreshAll() }
        }) {
            HStack(spacing: 8) {
                if viewModel.isRefreshing {
                    ProgressView()
                        .tint(DS.Adaptive.textPrimary)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(viewModel.isRefreshing ? "Syncing..." : "Sync All")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundColor(DS.Adaptive.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(DS.Adaptive.textTertiary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isRefreshing)
        .opacity(viewModel.isRefreshing ? 0.6 : 1)
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [BrandColors.goldBase.opacity(0.15), BrandColors.goldBase.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                Image(systemName: "link.badge.plus")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundColor(BrandColors.goldBase)
            }
            
            VStack(spacing: 6) {
                Text("No Connections Yet")
                    .font(.title3.weight(.bold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text("Connect your exchanges or wallets to automatically\ntrack your portfolio in one place.")
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
            
            // CTA: Navigate to Exchanges & Wallets
            NavigationLink(destination: PortfolioPaymentMethodsView()) {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Add Connection")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundColor(isDark ? .black : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: isDark
                                    ? [BrandColors.goldLight, BrandColors.goldBase]
                                    : [Color(red: 0.78, green: 0.62, blue: 0.14), Color(red: 0.66, green: 0.48, blue: 0.06)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 8)
            
            // Features list
            VStack(alignment: .leading, spacing: 10) {
                connectionFeatureRow(icon: "bolt.fill", color: .green, text: "Quick connect with Coinbase & more")
                connectionFeatureRow(icon: "key.fill", color: .orange, text: "API key support for Binance, KuCoin")
                connectionFeatureRow(icon: "wallet.pass.fill", color: .purple, text: "Track wallet addresses on-chain")
                connectionFeatureRow(icon: "cube.fill", color: BrandColors.goldBase, text: "Add gold, silver & other commodities")
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
                    )
            )
        }
        .padding(.vertical, 24)
    }
    
    private func connectionFeatureRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(color.opacity(0.12))
                    .frame(width: 28, height: 28)
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(color)
            }
            Text(text)
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
            Spacer()
        }
    }
    
    // MARK: - Accounts List
    
    private var accountsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Connected Accounts")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(DS.Adaptive.textTertiary)
                .padding(.leading, 4)
            
            ForEach(viewModel.accountHealths) { health in
                AccountHealthRow(health: health) {
                    Task {
                        await viewModel.refreshAccount(health.id)
                    }
                }
            }
        }
    }
}

// MARK: - Account Health Row

struct AccountHealthRow: View {
    let health: AccountHealth
    let onRefresh: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(health.status.color.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: health.status.icon)
                    .font(.system(size: 15))
                    .foregroundColor(health.status.color)
            }
            
            // Account info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(health.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Text(health.type == "wallet" ? "Wallet" : "Exchange")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(DS.Adaptive.textTertiary.opacity(0.12))
                        )
                }
                
                HStack(spacing: 6) {
                    Text(health.provider.capitalized)
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    Text("·")
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    Text(health.timeSinceSync)
                        .font(.caption)
                        .foregroundColor(health.status == .stale ? .orange : DS.Adaptive.textTertiary)
                }
            }
            
            Spacer()
            
            // Refresh button
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onRefresh()
            }) {
                Image(systemName: health.status == .syncing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(BrandColors.goldBase)
            }
            .disabled(health.status == .syncing)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(DS.Adaptive.stroke, lineWidth: 1)
                )
        )
    }
}

// MARK: - Preview

#if DEBUG
struct ConnectionHealthView_Previews: PreviewProvider {
    static var previews: some View {
        ConnectionHealthView()
    }
}
#endif
