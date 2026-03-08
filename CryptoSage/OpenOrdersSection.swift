//
//  OpenOrdersSection.swift
//  CryptoSage
//
//  Collapsible section showing open orders for the current trading pair.
//  Designed to be embedded in TradeView below the order book.
//

import SwiftUI

// MARK: - Open Orders Section

struct OpenOrdersSection: View {
    /// The trading symbol to filter orders by (e.g., "BTC", "BTCUSDT")
    let symbol: String
    
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var ordersManager = OpenOrdersManager.shared
    @ObservedObject private var paperTradingManager = PaperTradingManager.shared
    @ObservedObject private var demoModeManager = DemoModeManager.shared
    
    @State private var isExpanded: Bool = true
    @State private var showCancelAllConfirmation: Bool = false
    
    /// Whether we're in paper trading mode
    private var isPaperMode: Bool {
        PaperTradingManager.isEnabled
    }
    
    /// Whether we're in demo mode
    private var isDemoMode: Bool {
        demoModeManager.isDemoMode
    }
    
    /// Orders filtered for the current symbol
    private var symbolOrders: [OpenOrder] {
        ordersManager.orders(for: symbol)
    }
    
    /// Order count for badge
    private var orderCount: Int {
        symbolOrders.count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerRow
            
            // Content
            if isExpanded {
                if ordersManager.isLoading {
                    loadingView
                } else if symbolOrders.isEmpty {
                    emptyState
                } else {
                    ordersList
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
        )
        .onAppear {
            Task {
                await ordersManager.refreshOrders(for: symbol)
            }
        }
        .confirmationDialog(
            "Cancel All Orders",
            isPresented: $showCancelAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Cancel All \(orderCount) Orders", role: .destructive) {
                Task {
                    await ordersManager.cancelAllOrders(for: symbol)
                }
            }
            Button("Keep Orders", role: .cancel) {}
        } message: {
            Text("This will cancel all \(orderCount) open orders for \(extractBaseAsset(symbol)).")
        }
    }
    
    // MARK: - Header
    
    private var headerRow: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
            // Silently refresh when expanding (no visible indicator unless loading takes time)
            if !isExpanded {
                Task {
                    await ordersManager.refreshOrders(for: symbol)
                }
            }
        } label: {
            HStack(spacing: 10) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(orderCount > 0 ? Color.orange.opacity(0.15) : DS.Adaptive.overlay(0.05))
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: "list.bullet.clipboard")
                        .font(.system(size: 13))
                        .foregroundColor(orderCount > 0 ? .orange : DS.Adaptive.textTertiary)
                }
                
                // Title
                Text("Open Orders")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                // Count badge
                if orderCount > 0 {
                    Text("\(orderCount)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange))
                }
                
                Spacer()
                
                // Cancel all button (only when expanded and has multiple orders)
                if isExpanded && orderCount > 1 {
                    Button {
                        showCancelAllConfirmation = true
                    } label: {
                        Text("Cancel All")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.red.opacity(0.9))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(6)
                    }
                }
                
                // Expand/collapse chevron
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 8) {
            Divider().background(DS.Adaptive.divider)
            ForEach(0..<2, id: \.self) { _ in
                HStack(spacing: 8) {
                    // Side/type badge placeholder
                    ShimmerBar(height: 14, cornerRadius: 3)
                        .frame(width: 32)
                    // Symbol placeholder
                    ShimmerBar(height: 12, cornerRadius: 3)
                        .frame(width: 50)
                    Spacer()
                    // Price + qty placeholder
                    VStack(alignment: .trailing, spacing: 3) {
                        ShimmerBar(height: 11, cornerRadius: 2)
                            .frame(width: 60)
                        ShimmerBar(height: 9, cornerRadius: 2)
                            .frame(width: 40)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 14))
                .foregroundColor(DS.Adaptive.textTertiary.opacity(0.6))
            
            Text("No open orders for \(extractBaseAsset(symbol))")
                .font(.system(size: 12))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
    
    // MARK: - Orders List
    
    private var ordersList: some View {
        VStack(spacing: 8) {
            Divider()
                .background(DS.Adaptive.divider)
            
            ForEach(symbolOrders) { order in
                CompactOpenOrderRowView(order: order, isDemoMode: isDemoMode) {
                    Task {
                        await ordersManager.cancelOrder(order)
                    }
                }
            }
            
            // Error message if any
            if let error = ordersManager.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }
                .padding(.vertical, 4)
            }
            
            // Last refresh time
            if let lastRefresh = ordersManager.lastRefresh {
                Text("Updated \(formatRelativeTime(lastRefresh))")
                    .font(.system(size: 10))
                    .foregroundColor(DS.Adaptive.textTertiary.opacity(0.6))
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
    
    // MARK: - Helpers
    
    private func extractBaseAsset(_ symbol: String) -> String {
        let upper = symbol.uppercased()
        let quotes = ["USDT", "USD", "USDC", "BUSD", "EUR", "GBP", "BTC", "ETH"]
        for quote in quotes {
            if upper.hasSuffix(quote) {
                return String(upper.dropLast(quote.count))
            }
        }
        return upper
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 5 {
            return "just now"
        } else if seconds < 60 {
            return "\(seconds)s ago"
        } else if seconds < 3600 {
            return "\(seconds / 60)m ago"
        } else {
            return "\(seconds / 3600)h ago"
        }
    }
}

// MARK: - Preview

#if DEBUG
struct OpenOrdersSection_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            OpenOrdersSection(symbol: "BTC")
            OpenOrdersSection(symbol: "ETH")
        }
        .padding()
        .background(DS.Adaptive.background)
        .previewLayout(.sizeThatFits)
    }
}
#endif
