//
//  TradingAPIKeysView.swift
//  CryptoSage
//
//  Manage trading API keys for all connected exchanges.
//

import SwiftUI

struct TradingAPIKeysView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var connectedExchanges: [TradingExchange] = []
    @State private var showAddExchange = false
    @State private var exchangeToDelete: TradingExchange? = nil
    @State private var showDeleteConfirmation = false
    @State private var connectionStatus: [TradingExchange: ConnectionStatus] = [:]
    
    private var isDark: Bool { colorScheme == .dark }
    
    enum ConnectionStatus {
        case untested
        case testing
        case connected
        case failed(String)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            // Content
            ScrollView {
                VStack(spacing: 16) {
                    // Info Banner
                    infoBanner
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    
                    if connectedExchanges.isEmpty {
                        emptyStateView
                    } else {
                        // Connected Exchanges List
                        connectedExchangesList
                    }
                    
                    // Add Exchange Button
                    addExchangeButton
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                }
            }
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
        .onAppear {
            refreshConnectedExchanges()
        }
        .sheet(isPresented: $showAddExchange) {
            NavigationStack {
                TradingCredentialsSetupView()
            }
            .onDisappear {
                refreshConnectedExchanges()
            }
        }
        .alert("Remove Exchange", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                exchangeToDelete = nil
            }
            Button("Remove", role: .destructive) {
                if let exchange = exchangeToDelete {
                    removeExchange(exchange)
                }
            }
        } message: {
            if let exchange = exchangeToDelete {
                Text("Are you sure you want to remove \(exchange.displayName)? You'll need to re-enter your API keys to trade on this exchange again.")
            }
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            CSNavButton(
                icon: "chevron.left",
                action: { dismiss() }
            )
            
            Spacer()
            
            Text("Trading API Keys")
                .font(.headline.weight(.semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Spacer()
            
            // Refresh button
            Button(action: {
                #if os(iOS)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
                testAllConnections()
            }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(DS.Adaptive.background)
    }
    
    // MARK: - Info Banner
    
    private var infoBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Secure API Keys")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text("Your API keys are encrypted and stored locally in the iOS Keychain. Enable 'Spot Trading' permission when creating keys.")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.blue.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
    }
    
    // MARK: - Empty State
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 40)
            
            ZStack {
                Circle()
                    .fill(BrandColors.goldBase.opacity(0.1))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "key.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [BrandColors.goldBase, BrandColors.goldLight],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            
            Text("No Exchanges Connected")
                .font(.title3.weight(.semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Text("Connect an exchange to sync your portfolio and access real-time market data.")
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer().frame(height: 20)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Connected Exchanges List
    
    private var connectedExchangesList: some View {
        VStack(spacing: 0) {
            ForEach(connectedExchanges) { exchange in
                ExchangeCredentialRow(
                    exchange: exchange,
                    status: connectionStatus[exchange] ?? .untested,
                    onTest: { testConnection(exchange) },
                    onDelete: {
                        exchangeToDelete = exchange
                        showDeleteConfirmation = true
                    }
                )
                
                if exchange != connectedExchanges.last {
                    Divider()
                        .background(DS.Adaptive.stroke)
                        .padding(.horizontal, 16)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
    }
    
    // MARK: - Add Exchange Button
    
    private var addExchangeButton: some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            #endif
            showAddExchange = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                Text("Connect New Exchange")
                    .font(.headline.weight(.semibold))
            }
            .foregroundColor(isDark ? .black : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: isDark
                                ? [BrandColors.goldBase, BrandColors.goldLight]
                                : [Color(red: 0.78, green: 0.62, blue: 0.14), Color(red: 0.66, green: 0.48, blue: 0.06)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
        }
    }
    
    // MARK: - Actions
    
    private func refreshConnectedExchanges() {
        connectedExchanges = TradingCredentialsManager.shared.getConnectedExchanges()
    }
    
    private func removeExchange(_ exchange: TradingExchange) {
        try? TradingCredentialsManager.shared.deleteCredentials(for: exchange)
        exchangeToDelete = nil
        refreshConnectedExchanges()
        
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
    
    private func testConnection(_ exchange: TradingExchange) {
        connectionStatus[exchange] = .testing
        
        Task {
            do {
                let success = try await TradingExecutionService.shared.testConnection(exchange: exchange)
                await MainActor.run {
                    connectionStatus[exchange] = success ? .connected : .failed("Invalid credentials")
                    #if os(iOS)
                    UINotificationFeedbackGenerator().notificationOccurred(success ? .success : .error)
                    #endif
                }
            } catch {
                await MainActor.run {
                    connectionStatus[exchange] = .failed(error.localizedDescription)
                    #if os(iOS)
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    #endif
                }
            }
        }
    }
    
    private func testAllConnections() {
        for exchange in connectedExchanges {
            testConnection(exchange)
        }
    }
}

// MARK: - Exchange Credential Row

private struct ExchangeCredentialRow: View {
    let exchange: TradingExchange
    let status: TradingAPIKeysView.ConnectionStatus
    let onTest: () -> Void
    let onDelete: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        HStack(spacing: 12) {
            // Exchange Icon
            ZStack {
                Circle()
                    .fill(exchangeColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                
                exchangeIcon
                    .font(.system(size: 20))
                    .foregroundColor(exchangeColor)
            }
            
            // Exchange Info
            VStack(alignment: .leading, spacing: 3) {
                Text(exchange.displayName)
                    .font(.headline)
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                statusView
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 8) {
                // Test Button
                Button(action: onTest) {
                    Group {
                        if case .testing = status {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 14))
                        }
                    }
                    .frame(width: 32, height: 32)
                    .background(
                        Circle()
                            .fill(Color.blue.opacity(0.1))
                    )
                }
                .foregroundColor(.blue)
                .disabled(status.isTesting)
                
                // Delete Button
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(Color.red.opacity(0.1))
                        )
                }
                .foregroundColor(.red)
            }
        }
        .padding(16)
    }
    
    private var exchangeColor: Color {
        switch exchange {
        case .binance, .binanceUS: return .yellow
        case .coinbase: return .blue
        case .kraken: return .purple
        case .kucoin: return .green
        case .bybit: return .orange
        case .okx: return .gray
        }
    }
    
    @ViewBuilder
    private var exchangeIcon: some View {
        switch exchange {
        case .binance, .binanceUS:
            Image(systemName: "bitcoinsign.circle.fill")
        case .coinbase:
            Image(systemName: "dollarsign.circle.fill")
        case .kraken:
            Image(systemName: "waveform.circle.fill")
        case .kucoin:
            Image(systemName: "k.circle.fill")
        case .bybit:
            Image(systemName: "b.circle.fill")
        case .okx:
            Image(systemName: "o.circle.fill")
        }
    }
    
    @ViewBuilder
    private var statusView: some View {
        HStack(spacing: 4) {
            switch status {
            case .untested:
                Circle()
                    .fill(Color.gray)
                    .frame(width: 6, height: 6)
                Text("Not tested")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    
            case .testing:
                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)
                Text("Testing...")
                    .font(.caption)
                    .foregroundColor(.orange)
                    
            case .connected:
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("Connected")
                    .font(.caption)
                    .foregroundColor(.green)
                    
            case .failed(let error):
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(1)
            }
        }
    }
}

extension TradingAPIKeysView.ConnectionStatus {
    var isTesting: Bool {
        if case .testing = self { return true }
        return false
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        TradingAPIKeysView()
    }
    .preferredColorScheme(.dark)
}
