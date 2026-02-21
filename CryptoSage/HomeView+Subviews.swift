//
//  HomeView+Subviews.swift
//  CryptoSage
//
//  Extracted Home subviews to resolve duplication and compile issues.
//

import SwiftUI
import UIKit
import Combine

extension HomeView {

    // Shared currency formatter for transaction amounts — always shows 2 decimal places
    // for professional financial display (e.g., "$12,326.10" not "$12,326")
    private static let fiatFormatter0: NumberFormatter = {
        let nf = NumberFormatter()
        nf.numberStyle = .currency
        nf.currencyCode = CurrencyManager.currencyCode
        nf.maximumFractionDigits = 2
        nf.minimumFractionDigits = 2
        return nf
    }()

    static func formatUSD0(_ value: Double) -> String {
        return fiatFormatter0.string(from: NSNumber(value: value)) ?? String(format: "$%.2f", value)
    }
    
    /// Format per-unit price for display in transaction subtitles (e.g., "@ $69,248.00")
    static func formatPerUnitPrice(_ price: Double) -> String {
        let formatted = fiatFormatter0.string(from: NSNumber(value: price)) ?? String(format: "$%.2f", price)
        return "@ \(formatted)"
    }
    
    /// Format crypto amount with appropriate precision and comma grouping.
    /// Shows more decimals for small amounts, fewer for large amounts.
    /// Always shows at least 2 decimal places for professional financial display.
    static func formatCryptoAmount(_ quantity: Double, symbol: String, signed: Bool) -> String {
        let sign = signed ? "+" : "-"
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.usesGroupingSeparator = true
        nf.minimumFractionDigits = 2
        
        if quantity < 0.01 {
            nf.maximumFractionDigits = 6   // Micro amounts: "+0.000125 BTC"
        } else if quantity < 1 {
            nf.maximumFractionDigits = 4   // Fractional: "+0.5000 BTC"
        } else {
            nf.maximumFractionDigits = 2   // Standard: "+1.25 BTC", "+1,250.00 SOL"
        }
        
        let formatted = nf.string(from: NSNumber(value: quantity)) ?? String(format: "%.2f", quantity)
        return "\(sign)\(formatted) \(symbol)"
    }

    // Trending Section
    // PERFORMANCE FIX v22: trendingSection moved to HomeView.swift to access @State cachedTrendingCoins

    // Exchange Price Comparison Section
    var arbitrageSection: some View {
        ExchangePriceSection()
    }
    
    var whaleActivitySection: some View {
        WhaleActivityPreviewSection(
            onOpenFullView: { showWhaleActivityFullView = true }
        )
    }

    // Transactions Section
    enum TxDirection { case `in`, out }
    enum TxStatus: String { case pending = "Pending", failed = "Failed", completed = "Completed" }

    struct RecentTransaction: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let subtitle: String
        let cryptoAmountSigned: String
        let fiatAmount: String
        let direction: TxDirection
        let status: TxStatus?
        let hash: String?
        let date: Date
        let exchange: String?
        
        init(symbol: String, title: String, subtitle: String, cryptoAmountSigned: String, fiatAmount: String, direction: TxDirection, status: TxStatus?, hash: String?, date: Date, exchange: String? = nil) {
            self.symbol = symbol
            self.title = title
            self.subtitle = subtitle
            self.cryptoAmountSigned = cryptoAmountSigned
            self.fiatAmount = fiatAmount
            self.direction = direction
            self.status = status
            self.hash = hash
            self.date = date
            self.exchange = exchange
        }
    }

    enum TxFilter: String, CaseIterable { case all = "All", buys = "Buys", sells = "Sells", transfers = "Transfers", staking = "Staking" }

    @MainActor
    final class RecentTransactionsViewModel: ObservableObject {
        static let mockItems: [RecentTransaction] = [
            RecentTransaction(symbol: "BTC", title: "Buy BTC", subtitle: "Network fee $0.42", cryptoAmountSigned: "+1.25 BTC", fiatAmount: "$84,250.00", direction: .in, status: .completed, hash: "0x9c3a1f2b4c8e7d6f5a3b2c1d0e9f8a7b6c5d4e3f2a1b0c9d8e7f6a5b4c3d2e1f", date: Date().addingTimeInterval(-60*60*3), exchange: "Coinbase"),
            RecentTransaction(symbol: "ETH", title: "Sell ETH", subtitle: "Limit order", cryptoAmountSigned: "-12.50 ETH", fiatAmount: "$29,000.00", direction: .out, status: .completed, hash: "0x1ab2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2", date: Date().addingTimeInterval(-60*60*24), exchange: "Binance"),
            RecentTransaction(symbol: "SOL", title: "Stake SOL", subtitle: "APY 7.1%", cryptoAmountSigned: "+50.00 SOL", fiatAmount: "", direction: .in, status: .pending, hash: nil, date: Date().addingTimeInterval(-60*60*24*2), exchange: "Marinade")
        ]
        @Published var items: [RecentTransaction] = mockItems
        @Published var isLoading = false

        func transactions(filteredBy filter: TxFilter) -> [RecentTransaction] {
            switch filter {
            case .all: return items
            case .buys: return items.filter { $0.title.lowercased().contains("buy") }
            case .sells: return items.filter { $0.title.lowercased().contains("sell") }
            case .transfers: return items.filter { $0.title.lowercased().contains("send") || $0.title.lowercased().contains("transfer") }
            case .staking: return items.filter { $0.title.lowercased().contains("stake") }
            }
        }
    }

    struct TokenIcon: View {
        let symbol: String
        var size: CGFloat = 36
        private func imageURLForSymbol(_ symbol: String) -> URL? {
            let upper = symbol.uppercased()
            if let coin = MarketViewModel.shared.allCoins.first(where: { $0.symbol.uppercased() == upper }) {
                return coin.imageUrl
            }
            return nil
        }
        var body: some View {
            ZStack {
                // Lightweight placeholder to prevent layout shift while loading
                Circle().fill(DS.Adaptive.stroke)
                CoinImageView(symbol: symbol, url: imageURLForSymbol(symbol), size: size)
                    .clipShape(Circle())
            }
            .transaction { $0.disablesAnimations = true }
            .frame(width: size, height: size)
            .overlay(Circle().stroke(DS.Adaptive.strokeStrong, lineWidth: size < 40 ? 0.5 : 1))
        }
    }

    struct RecentTransactionRow: View {
        let tx: RecentTransaction
        @State private var expanded = false
        @State private var copiedHash = false

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                // Main row content
                HStack(alignment: .center, spacing: 10) {
                    // Left: Icon with direction badge
                    ZStack(alignment: .bottomTrailing) {
                        TokenIcon(symbol: tx.symbol, size: 38)
                        Circle()
                            .fill(tx.direction == .out ? Color.red : Color.green)
                            .frame(width: 12, height: 12)
                            .overlay(
                                Image(systemName: tx.direction == .out ? "arrow.up.right" : "arrow.down.left")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundColor(.white)
                            )
                            .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 0.5))
                            .offset(x: 2, y: 2)
                    }
                    
                    // Center: Title, status, and subtitle
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(tx.title)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(DS.Adaptive.textPrimary)
                            if let status = tx.status {
                                StatusBadge(status: status)
                            }
                        }
                        HStack(spacing: 4) {
                            if let exchange = tx.exchange {
                                Text(exchange)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(DS.Adaptive.textSecondary)
                                Text("·")
                                    .font(.system(size: 11))
                                    .foregroundStyle(DS.Adaptive.textTertiary)
                            }
                            Text(tx.subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(DS.Adaptive.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer(minLength: 6)
                    
                    // Right: Amounts and time
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(tx.cryptoAmountSigned)
                            .font(.system(size: 14, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(tx.direction == .out ? Color.red : Color.green)
                        if !tx.fiatAmount.isEmpty {
                            Text(tx.fiatAmount)
                                .font(.system(size: 12, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(DS.Adaptive.textSecondary)
                        }
                        Text(relativeTime(from: tx.date))
                            .font(.system(size: 10))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                    }
                    
                    // Chevron for expand/collapse - subtle styling
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary.opacity(0.7))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                        .animation(.easeInOut(duration: 0.2), value: expanded)
                }
                .padding(.vertical, 10)

                // Expanded details section
                if expanded {
                    TransactionDetailsCard(
                        tx: tx,
                        copiedHash: $copiedHash,
                        explorerURL: explorerURL()
                    )
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.snappy) { expanded.toggle(); haptic(.light) } }
            .swipeActions(edge: .trailing) {
                Button("Repeat") { haptic(.medium) }.tint(.blue)
                Button("Share") { haptic(.rigid) }.tint(.gray)
            }
            .contextMenu {
                if let hash = tx.hash, !hash.isEmpty {
                    Button {
                        #if os(iOS)
                        // SECURITY: Auto-clear clipboard after 60s for transaction hashes
                        SecurityManager.shared.secureCopy(hash)
                        #endif
                    } label: {
                        Label("Copy Hash", systemImage: "doc.on.doc")
                    }
                }
                if let url = explorerURL() {
                    Button {
                        #if os(iOS)
                        UIApplication.shared.open(url)
                        #endif
                    } label: {
                        Label("View in Explorer", systemImage: "safari")
                    }
                }
            }
            .overlay(
                Rectangle()
                    .fill(DS.Adaptive.divider)
                    .frame(height: 0.5),
                alignment: .bottom
            )
        }

        private func relativeTime(from date: Date) -> String {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter.localizedString(for: date, relativeTo: Date())
        }

        private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: style).impactOccurred()
            #endif
        }

        private func explorerURL() -> URL? {
            let sym = tx.symbol.uppercased()
            let hash = tx.hash?.trimmingCharacters(in: .whitespacesAndNewlines)
            switch sym {
            case "BTC":
                if let h = hash, !h.isEmpty { return URL(string: "https://mempool.space/tx/\(h)") }
                return URL(string: "https://mempool.space/")
            case "ETH":
                if let h = hash, !h.isEmpty { return URL(string: "https://etherscan.io/tx/\(h)") }
                return URL(string: "https://etherscan.io/")
            case "SOL":
                if let h = hash, !h.isEmpty { return URL(string: "https://solscan.io/tx/\(h)") }
                return URL(string: "https://solscan.io/")
            default:
                // SECURITY FIX: URL encode user input to prevent injection
                if let h = hash, !h.isEmpty,
                   let encoded = h.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
                    return URL(string: "https://blockchair.com/search?q=\(encoded)")
                }
                return nil
            }
        }
    }
    
    // MARK: - Transaction Row Subcomponents
    
    struct StatusBadge: View {
        let status: TxStatus
        
        var body: some View {
            Text(status.rawValue)
                .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(badgeColor)
                .clipShape(Capsule())
                .foregroundColor(badgeTextColor)
                .accessibilityLabel("Status: \(status.rawValue)")
        }
        
        private var badgeColor: Color {
            switch status {
            case .pending: return DS.Adaptive.gold.opacity(0.25)
            case .failed: return Color.red.opacity(0.25)
            case .completed: return Color.green.opacity(0.25)
            }
        }
        
        private var badgeTextColor: Color {
            switch status {
            case .pending: return DS.Adaptive.goldText
            case .failed: return Color.red
            case .completed: return Color.green
            }
        }
    }
    
    struct TransactionDetailsCard: View {
        let tx: RecentTransaction
        @Binding var copiedHash: Bool
        let explorerURL: URL?
        
        private var formattedDate: String {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: tx.date)
        }
        
        private var truncatedHash: String {
            guard let hash = tx.hash, hash.count > 20 else { return tx.hash ?? "" }
            let prefix = String(hash.prefix(10))
            let suffix = String(hash.suffix(8))
            return "\(prefix)...\(suffix)"
        }
        
        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                // Transaction hash section
                if let hash = tx.hash, !hash.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Transaction Hash")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                            .textCase(.uppercase)
                        
                        HStack(spacing: 8) {
                            Text(truncatedHash)
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                                .foregroundStyle(DS.Adaptive.textSecondary)
                                .textSelection(.enabled)
                            
                            Spacer()
                            
                            // Copy button
                            Button {
                                #if os(iOS)
                                // SECURITY: Auto-clear clipboard after 60s for transaction hashes
                                SecurityManager.shared.secureCopy(hash)
                                withAnimation { copiedHash = true }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    withAnimation { copiedHash = false }
                                }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                #endif
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: copiedHash ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(copiedHash ? "Copied" : "Copy")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(copiedHash ? .green : DS.Adaptive.goldText)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(copiedHash ? Color.green.opacity(0.15) : DS.Adaptive.gold.opacity(0.15))
                                )
                            }
                            .buttonStyle(.plain)
                            
                            // Explorer button
                            if let url = explorerURL {
                                Button {
                                    #if os(iOS)
                                    UIApplication.shared.open(url)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    #endif
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "safari")
                                            .font(.system(size: 11, weight: .semibold))
                                        Text("Explorer")
                                            .font(.system(size: 11, weight: .medium))
                                    }
                                    .foregroundColor(.blue)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(
                                        Capsule()
                                            .fill(Color.blue.opacity(0.15))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                
                // Date and exchange info
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Date")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DS.Adaptive.textTertiary)
                            .textCase(.uppercase)
                        Text(formattedDate)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DS.Adaptive.textSecondary)
                    }
                    
                    if let exchange = tx.exchange {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Exchange")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(DS.Adaptive.textTertiary)
                                .textCase(.uppercase)
                            Text(exchange)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(DS.Adaptive.textSecondary)
                        }
                    }
                    
                    Spacer()
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(DS.Adaptive.cardBackgroundElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Transaction Data Mode
    enum TransactionDataMode {
        case demo       // Demo mode: show sample transactions
        case paper      // Paper trading: show paper trades
        case portfolio  // Portfolio mode: show real portfolio transactions (renamed from "live")
        
        var displayName: String {
            switch self {
            case .demo: return "Demo"
            case .paper: return "Paper Trading"
            case .portfolio: return "Portfolio"
            }
        }
        
        var iconName: String {
            switch self {
            case .demo: return AppTradingMode.demo.icon      // Single source of truth
            case .paper: return AppTradingMode.paper.icon
            case .portfolio: return AppTradingMode.portfolio.icon
            }
        }
        
        var accentColor: Color {
            switch self {
            case .demo: return AppTradingMode.demo.color       // Single source of truth
            case .paper: return AppTradingMode.paper.color
            case .portfolio: return AppTradingMode.portfolio.color
            }
        }
    }
    
    struct RecentTransactionsSection: View {
        @State private var filter: TxFilter = .all
        @AppStorage("home.tx.filter") private var persistedFilterRaw: String = HomeView.TxFilter.all.rawValue
        private var persistedFilter: HomeView.TxFilter {
            get { HomeView.TxFilter(rawValue: persistedFilterRaw) ?? .all }
            set { persistedFilterRaw = newValue.rawValue }
        }
        @StateObject private var vm = RecentTransactionsViewModel()

        @EnvironmentObject var homeVM: HomeViewModel
        // PERFORMANCE FIX v21: Removed @EnvironmentObject var appState: AppState
        // AppState has 18+ @Published properties - only dismissHomeSubviews needed, use onReceive.
        // FIX v23: Replaced @ObservedObject with computed singleton access + debounced refresh.
        // PaperTradingManager has 9 @Published (lastKnownPrices fires on every price update).
        // DemoModeManager has 1 @Published. This section is lower on the page but still benefits
        // from reduced re-render frequency.
        private var demoModeManager: DemoModeManager { DemoModeManager.shared }
        private var paperTradingManager: PaperTradingManager { PaperTradingManager.shared }
        @State private var txModeTick: UInt = 0
        
        @State private var isActive: Bool = false
        @State private var openAll: Bool = false
        
        // Computed current mode
        private var currentMode: TransactionDataMode {
            if paperTradingManager.isPaperTradingEnabled {
                return .paper
            } else if demoModeManager.isDemoMode {
                return .demo
            } else {
                return .portfolio
            }
        }
        
        // Consolidated trigger for data refresh - combines multiple state values into one
        // to reduce the number of onChange handlers and prevent cascading updates
        private var dataRefreshTrigger: String {
            let mode = currentMode
            let relevantCount: Int
            switch mode {
            case .paper:
                relevantCount = paperTradingManager.paperTradeHistory.count
            case .portfolio:
                relevantCount = homeVM.portfolioVM.transactions.count
            case .demo:
                relevantCount = 0
            }
            return "\(mode)-\(relevantCount)"
        }
        
        // Convert paper trades to RecentTransaction format
        private func paperTradesToTransactions(_ trades: [PaperTrade]) -> [HomeView.RecentTransaction] {
            return trades.prefix(20).map { trade in
                let sym = PaperTradingManager.shared.parseSymbol(trade.symbol).base
                let isBuy = trade.side == .buy
                let title = (isBuy ? "Buy " : "Sell ") + sym
                let qtyStr = HomeView.formatCryptoAmount(trade.quantity, symbol: sym, signed: isBuy)
                let fiatStr = HomeView.formatUSD0(trade.totalValue)
                // Show order type and per-unit price in subtitle for clarity
                let priceStr = HomeView.formatPerUnitPrice(trade.price)
                let subtitle = "\(trade.orderType) · \(priceStr)"
                return HomeView.RecentTransaction(
                    symbol: sym,
                    title: title,
                    subtitle: subtitle,
                    cryptoAmountSigned: qtyStr,
                    fiatAmount: fiatStr,
                    direction: isBuy ? .in : .out,
                    status: .completed,
                    hash: nil,
                    date: trade.timestamp,
                    exchange: "Paper Trading"
                )
            }
        }
        
        // Sync from portfolio for live mode
        private func syncFromPortfolio() {
            let txs = homeVM.portfolioVM.transactions
            let mapped: [HomeView.RecentTransaction] = txs.map { tx in
                let sym = tx.coinSymbol.uppercased()
                let isBuy = tx.isBuy
                let title = (isBuy ? "Buy " : "Sell ") + sym
                let qtyStr = HomeView.formatCryptoAmount(tx.quantity, symbol: sym, signed: isBuy)
                let fiat = tx.pricePerUnit * tx.quantity
                let fiatStr = HomeView.formatUSD0(fiat)
                let priceStr = HomeView.formatPerUnitPrice(tx.pricePerUnit)
                return HomeView.RecentTransaction(
                    symbol: sym,
                    title: title,
                    subtitle: priceStr,
                    cryptoAmountSigned: qtyStr,
                    fiatAmount: fiatStr,
                    direction: isBuy ? .in : .out,
                    status: .completed,
                    hash: nil,
                    date: tx.date,
                    exchange: nil
                )
            }
            vm.items = mapped
        }
        
        // Refresh data based on current mode
        private func refreshData() {
            switch currentMode {
            case .demo:
                vm.items = RecentTransactionsViewModel.mockItems
            case .paper:
                vm.items = paperTradesToTransactions(paperTradingManager.paperTradeHistory)
            case .portfolio:
                syncFromPortfolio()
            }
        }

        private func startPeriodicRefresh() {
            isActive = true
            Task { @MainActor in
                while isActive {
                    try? await Task.sleep(nanoseconds: 60_000_000_000) // 60s
                    refreshData()
                }
            }
        }

        // MARK: - Helper Views (extracted to reduce type-checking complexity)
        
        @ViewBuilder
        private var headerSection: some View {
            // Clean header - mode is shown globally via TradingModeSegmentedControl
            HStack(alignment: .center, spacing: 8) {
                GoldHeaderGlyph(systemName: "clock.arrow.circlepath")
                
                Text("Recent Transactions")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Spacer()
            }
        }
        
        @ViewBuilder
        private var navigationLinkSection: some View {
            EmptyView()
                .navigationDestination(isPresented: $openAll) {
                    AllTransactionsView()
                }
        }
        
        @ViewBuilder
        private var filterChipsSection: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TxFilter.allCases, id: \.self) { f in
                        FilterChipSmall(title: f.rawValue, selected: f == filter) {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            filter = f
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
        }
        
        @ViewBuilder
        private var transactionListSection: some View {
            let filteredTxs = vm.transactions(filteredBy: filter)
            if filteredTxs.isEmpty {
                TransactionEmptyState(mode: currentMode, filter: filter)
                    .padding(.vertical, 4)
            } else {
                // Show only first 3 transactions on homepage for compactness
                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredTxs.prefix(3))) { tx in
                        RecentTransactionRow(tx: tx)
                    }
                }
                .redacted(reason: vm.isLoading ? .placeholder : RedactionReasons())
            }
        }
        
        @ViewBuilder
        private var viewAllTransactionsButton: some View {
            SectionCTAButton(
                title: "View All Transactions",
                icon: "clock.arrow.circlepath",
                compact: true
            ) {
                openAll = true
            }
        }
        
        @ViewBuilder
        private var cardContent: some View {
            let hasTransactions = !vm.transactions(filteredBy: filter).isEmpty
            
            VStack(alignment: .leading, spacing: 8) {
                // Header
                headerSection
                
                navigationLinkSection
                
                Divider()
                    .background(DS.Adaptive.divider)
                
                // Transaction rows
                transactionListSection
                
                // CTA Button - only show when there are actual transactions to view
                if hasTransactions {
                    viewAllTransactionsButton
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
        }

        var body: some View {
            // FIX v23: Reference tick to trigger re-renders on debounced mode changes
            let _ = txModeTick
            
            CardContainer {
                cardContent
            }
            .onAppear(perform: handleOnAppear)
            .onChange(of: filter) { _, new in
                DispatchQueue.main.async { persistedFilterRaw = new.rawValue }
            }
            // Consolidated onChange handler for data refresh - reduces SwiftUI view updates
            .onChange(of: dataRefreshTrigger) { _, _ in
                DispatchQueue.main.async { refreshData() }
            }
            // PERFORMANCE FIX v21: Use targeted onReceive instead of @EnvironmentObject var appState
            .onReceive(AppState.shared.$dismissHomeSubviews) { shouldDismiss in
                // Defer to avoid "Modifying state during view update"
                DispatchQueue.main.async {
                    if shouldDismiss && openAll {
                        openAll = false
                        AppState.shared.dismissHomeSubviews = false
                    }
                }
            }
            // FIX v23: Debounced mode manager observation (replaces @ObservedObject)
            .onReceive(PaperTradingManager.shared.objectWillChange.debounce(for: .seconds(5), scheduler: DispatchQueue.main)) { _ in
                guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
                txModeTick &+= 1
            }
            .onReceive(DemoModeManager.shared.objectWillChange.debounce(for: .seconds(1), scheduler: DispatchQueue.main)) { _ in
                txModeTick &+= 1
            }
            .onDisappear {
                isActive = false
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                // Defer to avoid "Modifying state during view update"
                DispatchQueue.main.async {
                    refreshData()
                }
            }
        }
        
        private func handleOnAppear() {
            DispatchQueue.main.async {
                filter = persistedFilter
                refreshData()
                startPeriodicRefresh()
            }
            // Warm logo cache in the background
            Task {
                await CoinLogoPrefetcher.shared.prefetchTopCoins(count: 36)
                await CoinLogoPrefetcher.shared.prefetch(symbols: vm.items.map { $0.symbol })
            }
        }

        // Compact filter chip for homepage transactions section - premium glass style via shared tintedCapsuleChip
        private struct FilterChipSmall: View {
            let title: String
            let selected: Bool
            let onTap: () -> Void
            @Environment(\.colorScheme) private var colorScheme
            
            private var isDark: Bool { colorScheme == .dark }
            
            var body: some View {
                Button(action: onTap) {
                    Text(title)
                        .font(.caption2.weight(.bold))
                        .lineLimit(1)
                        .foregroundStyle(selected ? TintedChipStyle.selectedText(isDark: isDark) : DS.Adaptive.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .frame(minHeight: 32)
                        .tintedCapsuleChip(isSelected: selected, isDark: isDark)
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Transaction Mode Banner
    struct TransactionModeBanner: View {
        let mode: TransactionDataMode
        @Environment(\.colorScheme) private var colorScheme
        
        // Darker variants for light mode text contrast
        private var textColor: Color {
            let isDark = colorScheme == .dark
            switch mode {
            case .demo:
                return isDark ? mode.accentColor : Color(red: 0.70, green: 0.55, blue: 0.10)
            case .paper:
                return isDark ? mode.accentColor : Color(red: 0.15, green: 0.35, blue: 0.70)
            case .portfolio:
                return isDark ? mode.accentColor : Color(red: 0.15, green: 0.55, blue: 0.25)
            }
        }
        
        /// Maps TransactionDataMode to AppTradingMode for label sourcing
        private var appMode: AppTradingMode {
            switch mode {
            case .demo: return .demo
            case .paper: return .paper
            case .portfolio: return .portfolio
            }
        }
        
        var body: some View {
            let isDark = colorScheme == .dark
            let modeColor = mode.accentColor
            
            HStack(spacing: 10) {
                // Icon with glass background circle
                ZStack {
                    Circle()
                        .fill(modeColor.opacity(isDark ? 0.12 : 0.08))
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(isDark ? 0.05 : 0.15), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                    Circle()
                        .stroke(modeColor.opacity(isDark ? 0.25 : 0.15), lineWidth: 0.5)
                    Image(systemName: mode.iconName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(textColor)
                }
                .frame(width: 24, height: 24)
                
                // Active mode label — uses AppTradingMode.displayName for consistency
                Text("\(appMode.displayName) Active")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(textColor)
                
                Spacer()
                
                // Subtitle pill — glass-styled to match ModeBadge
                Text(mode == .demo ? "Sample data" : "Virtual trades")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(modeColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        ZStack {
                            Capsule()
                                .fill(modeColor.opacity(isDark ? 0.12 : 0.07))
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.white.opacity(isDark ? 0.04 : 0.12), Color.clear],
                                        startPoint: .top,
                                        endPoint: .center
                                    )
                                )
                        }
                    )
                    .overlay(
                        Capsule()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        modeColor.opacity(isDark ? 0.35 : 0.22),
                                        modeColor.opacity(isDark ? 0.12 : 0.06)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: isDark ? 0.5 : 0.8
                            )
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(modeColor.opacity(isDark ? 0.06 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(modeColor.opacity(isDark ? 0.15 : 0.25), lineWidth: 0.5)
            )
        }
    }
    
    // MARK: - Transaction Empty State
    struct TransactionEmptyState: View {
        let mode: TransactionDataMode
        let filter: TxFilter
        @State private var isAnimating = false
        @Environment(\.colorScheme) private var colorScheme
        
        private var isDark: Bool { colorScheme == .dark }
        private var goldLight: Color { BrandColors.goldLight }
        private var goldBase: Color { BrandColors.goldBase }
        
        private var goldAccent: LinearGradient {
            isDark
                ? LinearGradient(colors: [goldLight, goldBase], startPoint: .topLeading, endPoint: .bottomTrailing)
                : LinearGradient(colors: [goldBase, BrandColors.goldDark], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        
        private var message: String {
            if filter != .all {
                return "No \(filter.rawValue.lowercased()) found"
            }
            
            switch mode {
            case .demo:
                return "Demo transactions will appear here"
            case .paper:
                return "Your paper trades will appear here when you make virtual trades"
            case .portfolio:
                return "Connect an exchange or add manual transactions to get started."
            }
        }
        
        private var iconName: String {
            if filter != .all {
                return "magnifyingglass"
            }
            switch mode {
            case .demo: return AppTradingMode.demo.icon
            case .paper: return AppTradingMode.paper.icon
            case .portfolio: return AppTradingMode.portfolio.icon
            }
        }
        
        private var iconColor: Color {
            switch mode {
            case .demo: return AppTradingMode.demo.color
            case .paper: return AppTradingMode.paper.color
            case .portfolio: return DS.Adaptive.textTertiary
            }
        }
        
        var body: some View {
            VStack(spacing: 8) {
                // Compact animated icon
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.1))
                        .frame(width: 36, height: 36)
                    
                    Circle()
                        .stroke(iconColor.opacity(0.2), lineWidth: 1)
                        .frame(width: 36, height: 36)
                        .scaleEffect(isAnimating ? 1.15 : 1.0)
                        .opacity(isAnimating ? 0 : 1)
                    
                    Image(systemName: iconName)
                        .font(.system(size: 15, weight: .light))
                        .foregroundColor(iconColor)
                }
                
                VStack(spacing: 3) {
                    if filter != .all {
                        Text("No Results")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                    }
                    
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(DS.Adaptive.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                
                if mode == .portfolio && filter == .all {
                    NavigationLink(destination: PortfolioPaymentMethodsView()) {
                        HStack(spacing: 5) {
                            Image(systemName: "link.circle.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(goldAccent)
                            Text("Connect Exchange")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(DS.Adaptive.textPrimary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            ZStack {
                                Capsule()
                                    .fill(
                                        RadialGradient(
                                            colors: isDark
                                                ? [goldBase.opacity(0.1), Color.white.opacity(0.05)]
                                                : [goldBase.opacity(0.06), Color.black.opacity(0.02)],
                                            center: .top,
                                            startRadius: 0,
                                            endRadius: 40
                                        )
                                    )
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.white.opacity(isDark ? 0.1 : 0.45), Color.white.opacity(0)],
                                            startPoint: .top,
                                            endPoint: .center
                                        )
                                    )
                            }
                        )
                        .overlay(
                            Capsule()
                                .stroke(
                                    LinearGradient(
                                        colors: isDark
                                            ? [goldLight.opacity(0.4), goldBase.opacity(0.15)]
                                            : [goldBase.opacity(0.3), goldBase.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            // MEMORY FIX v16: Removed .repeatForever animation — causes ~9 MB/s leak
            // when many instances run simultaneously on the home screen.
        }
    }

    var transactionsSection: some View { RecentTransactionsSection() }

    struct AllTransactionsView: View {
        @Environment(\.dismiss) private var dismiss
        @StateObject private var vm = HomeView.RecentTransactionsViewModel()
        @State private var filter: HomeView.TxFilter = .all
        @State private var showModeMenu: Bool = false

        @EnvironmentObject var homeVM: HomeViewModel
        // FIX v23: Replaced @ObservedObject with computed singleton access (same pattern as RecentTransactionsSection)
        private var demoModeManager: DemoModeManager { DemoModeManager.shared }
        private var paperTradingManager: PaperTradingManager { PaperTradingManager.shared }
        
        private let impactLight = UIImpactFeedbackGenerator(style: .light)
        
        // Computed current mode
        private var currentMode: TransactionDataMode {
            if paperTradingManager.isPaperTradingEnabled {
                return .paper
            } else if demoModeManager.isDemoMode {
                return .demo
            } else {
                return .portfolio
            }
        }
        
        // Convert paper trades to RecentTransaction format
        private func paperTradesToTransactions(_ trades: [PaperTrade]) -> [HomeView.RecentTransaction] {
            return trades.map { trade in
                let sym = PaperTradingManager.shared.parseSymbol(trade.symbol).base
                let isBuy = trade.side == .buy
                let title = (isBuy ? "Buy " : "Sell ") + sym
                let qtyStr = HomeView.formatCryptoAmount(trade.quantity, symbol: sym, signed: isBuy)
                let fiatStr = HomeView.formatUSD0(trade.totalValue)
                // Show order type and per-unit price in subtitle for clarity
                let priceStr = HomeView.formatPerUnitPrice(trade.price)
                let subtitle = "\(trade.orderType) · \(priceStr)"
                return HomeView.RecentTransaction(
                    symbol: sym,
                    title: title,
                    subtitle: subtitle,
                    cryptoAmountSigned: qtyStr,
                    fiatAmount: fiatStr,
                    direction: isBuy ? .in : .out,
                    status: .completed,
                    hash: nil,
                    date: trade.timestamp,
                    exchange: "Paper Trading"
                )
            }
        }

        private func syncFromPortfolio() {
            let txs = homeVM.portfolioVM.transactions
            let mapped: [HomeView.RecentTransaction] = txs.map { tx in
                let sym = tx.coinSymbol.uppercased()
                let isBuy = tx.isBuy
                let title = (isBuy ? "Buy " : "Sell ") + sym
                let qtyStr = HomeView.formatCryptoAmount(tx.quantity, symbol: sym, signed: isBuy)
                let fiat = tx.pricePerUnit * tx.quantity
                let fiatStr = HomeView.formatUSD0(fiat)
                let priceStr = HomeView.formatPerUnitPrice(tx.pricePerUnit)
                return HomeView.RecentTransaction(
                    symbol: sym,
                    title: title,
                    subtitle: priceStr,
                    cryptoAmountSigned: qtyStr,
                    fiatAmount: fiatStr,
                    direction: isBuy ? .in : .out,
                    status: .completed,
                    hash: nil,
                    date: tx.date,
                    exchange: nil
                )
            }
            vm.items = mapped
        }
        
        // Refresh data based on current mode
        private func refreshData() {
            switch currentMode {
            case .demo:
                vm.items = HomeView.RecentTransactionsViewModel.mockItems
            case .paper:
                vm.items = paperTradesToTransactions(paperTradingManager.paperTradeHistory)
            case .portfolio:
                syncFromPortfolio()
            }
        }

        var body: some View {
            VStack(spacing: 0) {
                // Unified header using SubpageHeaderBar for consistency
                SubpageHeaderBar(
                    title: "Transactions",
                    onDismiss: { dismiss() }
                ) {
                    // Mode menu button on right
                    modeMenuButton
                }
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 12) {
                        // Mode banner (if not portfolio mode)
                        if currentMode != .portfolio {
                            TransactionModeBanner(mode: currentMode)
                                .padding(.horizontal, 16)
                                .padding(.top, 4)
                        }
                        
                        // Filter chips - responsive layout
                        filterChipsRow
                            .padding(.top, currentMode == .portfolio ? 4 : 0)

                        // Transaction list or empty state
                        let filteredTxs = vm.transactions(filteredBy: filter)
                        if filteredTxs.isEmpty {
                            TransactionEmptyState(mode: currentMode, filter: filter)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 40)
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredTxs) { tx in
                                    HomeView.RecentTransactionRow(tx: tx)
                                        .padding(.horizontal, 16)
                                }
                            }
                            .padding(.bottom, 12)
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .navigationBarHidden(true)
            .enableInteractivePopGesture()
            .edgeSwipeToDismiss(onDismiss: { dismiss() })
            .background(DS.Adaptive.background.ignoresSafeArea())
            .onAppear {
                impactLight.prepare()
                DispatchQueue.main.async { refreshData() }
            }
            .onChange(of: demoModeManager.isDemoMode) { _, _ in
                DispatchQueue.main.async { refreshData() }
            }
            .onChange(of: paperTradingManager.isPaperTradingEnabled) { _, _ in
                DispatchQueue.main.async { refreshData() }
            }
            .onChange(of: paperTradingManager.paperTradeHistory.count) { _, _ in
                if currentMode == .paper {
                    DispatchQueue.main.async { refreshData() }
                }
            }
            .onChange(of: homeVM.portfolioVM.transactions.count) { _, _ in
                if currentMode == .portfolio {
                    DispatchQueue.main.async { refreshData() }
                }
            }
        }
        
        // MARK: - Mode Menu Button
        
        private var modeMenuButton: some View {
            Menu {
                // Current mode indicator
                Label("Current: \(currentMode.displayName)", systemImage: currentMode.iconName)
                
                Divider()
                
                // Toggle demo mode (only available when no connected accounts)
                let hasConnectedAccounts = !ConnectedAccountsManager.shared.accounts.isEmpty
                if !hasConnectedAccounts || demoModeManager.isDemoMode {
                    Button {
                        impactLight.impactOccurred()
                        if demoModeManager.isDemoMode {
                            demoModeManager.disableDemoMode()
                        } else {
                            paperTradingManager.disablePaperTrading()
                            demoModeManager.enableDemoMode()
                        }
                    } label: {
                        Label(demoModeManager.isDemoMode ? "Exit Demo Mode" : "Enable Demo Mode", systemImage: "wand.and.stars")
                    }
                }
                
                // Toggle paper trading
                Button {
                    impactLight.impactOccurred()
                    if paperTradingManager.isPaperTradingEnabled {
                        paperTradingManager.disablePaperTrading()
                    } else {
                        demoModeManager.disableDemoMode()
                        paperTradingManager.enablePaperTrading()
                    }
                } label: {
                    Label(paperTradingManager.isPaperTradingEnabled ? "Exit Paper Trading" : "Enable Paper Trading", systemImage: "doc.text.fill")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(DS.Adaptive.chipBackground))
                    .overlay(Circle().stroke(DS.Adaptive.stroke, lineWidth: 0.8))
            }
        }
        
        // MARK: - Filter Chips Row
        
        private var filterChipsRow: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(HomeView.TxFilter.allCases, id: \.self) { f in
                        FilterChip(title: f.rawValue, selected: f == filter) {
                            impactLight.impactOccurred()
                            filter = f
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }

        // Compact chip for transaction filters - premium glass style via shared tintedCapsuleChip
        private struct FilterChip: View {
            let title: String
            let selected: Bool
            let onTap: () -> Void
            @Environment(\.colorScheme) private var colorScheme
            
            private var isDark: Bool { colorScheme == .dark }
            
            var body: some View {
                Button(action: onTap) {
                    Text(title)
                        .font(.caption2.weight(.bold))
                        .lineLimit(1)
                        .foregroundStyle(selected ? TintedChipStyle.selectedText(isDark: isDark) : DS.Adaptive.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .frame(minHeight: 32)
                        .tintedCapsuleChip(isSelected: selected, isDark: isDark)
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private struct CommunityRow: View {
        let title: String
        let subtitle: String
        let systemImage: String?
        let assetName: String?
        let domain: String?
        var iconColor: Color = DS.Adaptive.gold
        let action: () -> Void
        var body: some View {
            Button(action: action) {
                HStack(spacing: 10) {
                    #if canImport(UIKit)
                    if let asset = assetName, UIImage(named: asset) != nil {
                        Image(asset)
                            .resizable()
                            .renderingMode(.original)
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                    } else if let host = domain, let url = URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64") {
                        // PERFORMANCE FIX: Use CachingAsyncImage instead of AsyncImage
                        // AsyncImage reloads on every appearance without caching, causing unnecessary network requests
                        CachingAsyncImage(url: url, referer: nil, maxPixel: 64)
                            .frame(width: 18, height: 18)
                            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                            .overlay {
                                // Fallback to SF Symbol if no image loaded
                                if let system = systemImage {
                                    Image(systemName: system)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(iconColor)
                                        .opacity(0) // Will be shown by CachingAsyncImage's placeholder
                                }
                            }
                    } else if let system = systemImage {
                        Image(systemName: system)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(iconColor)
                            .frame(width: 18)
                    }
                    #else
                    if let system = systemImage {
                        Image(systemName: system)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(iconColor)
                            .frame(width: 18)
                    }
                    #endif
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DS.Adaptive.textPrimary)
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(DS.Adaptive.textSecondary)
                    }
                    Spacer(minLength: 6)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DS.Adaptive.textSecondary)
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .overlay(
                Rectangle()
                    .fill(DS.Adaptive.divider)
                    .frame(height: 0.5),
                alignment: .bottom
            )
        }
    }

    var communitySection: some View {
        SocialTradingPreviewSection(
            onLeaderboardTapped: {
                // Navigate to Social Tab -> Leaderboard
                NotificationCenter.default.post(name: .openSocialTab, object: "leaderboard")
            }
        )
    }
    
    var communitySocialLinksSection: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 6) {
                // Integrated gold icon header - consistent with other sections
                HStack(alignment: .center, spacing: 8) {
                    GoldHeaderGlyph(systemName: "bubble.left.and.bubble.right.fill")
                    
                    Text("Community")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Spacer()
                }
                
                Text("Join the discussion with other traders.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                VStack(spacing: 0) {
                    CommunityRow(
                        title: "Open Forum",
                        subtitle: "Discuss strategies and insights",
                        systemImage: "bubble.left.and.bubble.right",
                        assetName: nil,
                        domain: nil,
                        iconColor: AppTradingMode.paper.color
                    ) {
                        // Opens the Social tab forum
                        NotificationCenter.default.post(name: .openSocialTab, object: "feed")
                    }
                    
                    CommunityRow(
                        title: "Discord",
                        subtitle: "Chat with the community",
                        systemImage: "message.fill",
                        assetName: nil,
                        domain: nil,
                        iconColor: Color(red: 0.34, green: 0.40, blue: 0.95)
                    ) {
                        if let url = URL(string: "https://discord.gg/cryptosage") {
                            UIApplication.shared.open(url)
                        }
                    }
                    
                    CommunityRow(
                        title: "Telegram",
                        subtitle: "Get instant updates",
                        systemImage: "paperplane.fill",
                        assetName: nil,
                        domain: nil,
                        iconColor: Color(red: 0.16, green: 0.67, blue: 0.89)
                    ) {
                        if let url = URL(string: "https://t.me/cryptosageai") {
                            UIApplication.shared.open(url)
                        }
                    }
                    
                    CommunityRow(
                        title: "X (Twitter)",
                        subtitle: "Follow @cryptosageai",
                        systemImage: "at",
                        assetName: nil,
                        domain: nil,
                        iconColor: DS.Adaptive.textPrimary
                    ) {
                        // Opens @cryptosageai on X/Twitter
                        if let url = URL(string: "https://x.com/cryptosageai") {
                            UIApplication.shared.open(url)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
        }
    }

    var footer: some View {
        VStack(spacing: 8) {
            // Disclaimer
            Text("All information is for educational purposes only and does not constitute financial advice. Cryptocurrency investments carry risk.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            
            // Copyright
            Text("© 2026 CryptoSage AI. All rights reserved.")
                .font(.caption2)
                .foregroundStyle(.quaternary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: - Social Trading Preview Section

/// A preview section for Leaderboard features shown on the Home page
struct SocialTradingPreviewSection: View {
    var onFeedTapped: (() -> Void)? = nil  // Legacy: kept for API compat
    let onLeaderboardTapped: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    // PERFORMANCE FIX v19: Removed @StateObject/@ObservedObject observations of
    // SocialService (10 @Published), LeaderboardEngine (7 @Published),
    // SubscriptionManager (6 @Published), PaperTradingManager (7 @Published).
    // Total: 30 @Published properties causing re-renders on every change.
    // Replaced with @State snapshots updated via debounced onReceive.
    
    // Cached snapshots
    @State private var cachedLeaderboard: [LeaderboardEntry] = LeaderboardEngine.shared.currentLeaderboard
    @State private var cachedCurrentProfile: UserProfile? = SocialService.shared.currentProfile
    @State private var cachedIsPaperTrading: Bool = PaperTradingManager.shared.isPaperTradingEnabled
    

    
    /// Determine which leaderboard mode to show based on user's trading mode + subscription
    private var currentLeaderboardMode: LeaderboardTradingMode {
        let hasPaperAccess = SubscriptionManager.shared.hasAccess(to: .paperTrading)
        return (hasPaperAccess && cachedIsPaperTrading) ? .paper : .portfolio
    }
    
    // Top traders from leaderboard or fallback to sample data
    private var topTraders: [(rank: Int, name: String, roi: Double, color: Color, avatarPresetId: String?)] {
        if cachedLeaderboard.count >= 3 {
            return cachedLeaderboard.prefix(3).enumerated().map { index, entry in
                let colors: [Color] = [.yellow, .gray, .orange]
                return (index + 1, entry.username, entry.pnlPercent, colors[index], entry.avatarPresetId)
            }
        }
        // Fallback sample data based on current mode with avatar presets
        if localLeaderboardMode == .paper {
            return [
                (1, "paper_legend", 385.4, .yellow, "crypto_bitcoin"),
                (2, "sim_whale", 295.2, .gray, "animal_whale"),
                (3, "virtual_victor", 268.5, .orange, "crypto_chart")
            ]
        } else {
            return [
                (1, "crypto_legend", 85.4, .yellow, "special_crown"),
                (2, "whale_hunter", 65.2, .gray, "animal_shark"),
                (3, "moon_sniper", 58.5, .orange, "crypto_moon")
            ]
        }
    }
    
    // Current user's rank (uses cached snapshots)
    private var userRank: Int? {
        guard let profile = cachedCurrentProfile else { return nil }
        return cachedLeaderboard.first(where: { $0.userId == profile.id })?.rank
    }
    
    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 10) {
                // Header with trading mode toggle
                headerView
                
                Divider()
                    .background(DS.Adaptive.divider)
                
                // Mini Leaderboard with Your Rank
                leaderboardPreview
                
                // View Full Leaderboard CTA
                leaderboardButton
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
        }
        .task {
            // Fetch leaderboard based on current trading mode
            _ = try? await LeaderboardEngine.shared.fetchLeaderboard(
                category: .pnlPercent,
                period: .month,
                tradingMode: currentLeaderboardMode
            )
            // Sync initial snapshots after fetching
            refreshSocialSnapshots()
        }
        // PERFORMANCE FIX v19: Debounced observation instead of @StateObject
        .onReceive(
            SocialService.shared.objectWillChange
                .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
        ) { _ in
            guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
            cachedCurrentProfile = SocialService.shared.currentProfile
        }
        .onReceive(
            LeaderboardEngine.shared.objectWillChange
                .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
        ) { _ in
            guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
            cachedLeaderboard = LeaderboardEngine.shared.currentLeaderboard
        }
        .onReceive(
            PaperTradingManager.shared.objectWillChange
                .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
        ) { _ in
            let newValue = PaperTradingManager.shared.isPaperTradingEnabled
            guard newValue != cachedIsPaperTrading else { return }
            cachedIsPaperTrading = newValue
            // Refresh leaderboard when trading mode changes
            Task {
                _ = try? await LeaderboardEngine.shared.fetchLeaderboard(
                    category: .pnlPercent,
                    period: .month,
                    tradingMode: currentLeaderboardMode,
                    forceRefresh: true
                )
            }
        }
    }

    @State private var localLeaderboardMode: LeaderboardTradingMode = {
        // Smart default: Portfolio for free users, Paper for Pro+ with paper trading
        let hasPaperAccess = SubscriptionManager.shared.hasAccess(to: .paperTrading)
        let isPaperEnabled = PaperTradingManager.shared.isPaperTradingEnabled
        return (hasPaperAccess && isPaperEnabled) ? .paper : .portfolio
    }()
    
    private var headerView: some View {
        HStack(alignment: .center, spacing: 8) {
            GoldHeaderGlyph(systemName: "trophy.fill")
            
            Text("Leaderboard")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Spacer()
            
            // Compact Paper / Portfolio toggle
            HStack(spacing: 0) {
                ForEach(LeaderboardTradingMode.allCases, id: \.self) { mode in
                    let isSelected = mode == localLeaderboardMode
                    
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            localLeaderboardMode = mode
                        }
                        Task {
                            await LeaderboardEngine.shared.switchTradingMode(mode)
                            refreshSocialSnapshots()
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(isSelected ? mode.color : mode.color.opacity(0.4))
                                .frame(width: 5, height: 5)
                            
                            Text(mode.shortName)
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(mode.color.opacity(0.12))
                                    .overlay(
                                        Capsule()
                                            .stroke(mode.color.opacity(0.4), lineWidth: 0.5)
                                    )
                            }
                        }
                        .foregroundStyle(isSelected ? mode.color : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(
                Capsule()
                    .fill(DS.Adaptive.chipBackground)
            )
        }
    }
    
    // MARK: - Leaderboard Preview
    
    @State private var showJoinLeaderboardSheet = false
    
    /// Whether the current user is already enrolled on the leaderboard
    private var isEnrolledOnLeaderboard: Bool {
        cachedCurrentProfile?.showOnLeaderboard == true
    }
    
    private var leaderboardPreview: some View {
        VStack(spacing: 6) {
            // Header: "Top Traders" with contextual right badge
            HStack {
                Text("Top Traders")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if let rank = userRank {
                    // User is ranked — show their position
                    HStack(spacing: 4) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(BrandColors.goldBase.opacity(0.8))
                        Text("Your Rank:")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("#\(rank)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(BrandColors.goldBase)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(BrandColors.goldBase.opacity(0.12))
                    )
                } else if !isEnrolledOnLeaderboard {
                    // User has no profile OR has profile but NOT enrolled — "Join" opens sign-up sheet
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showJoinLeaderboardSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 9))
                            Text("Join Leaderboard")
                                .font(.system(size: 10, weight: .semibold))
                        }
                    }
                    .buttonStyle(
                        PremiumCompactCTAStyle(
                            height: 28,
                            horizontalPadding: 11,
                            cornerRadius: 14,
                            font: .system(size: 11, weight: .semibold)
                        )
                    )
                }
            }
            .padding(.bottom, 2)
            
            ForEach(topTraders, id: \.rank) { trader in
                compactTraderRow(rank: trader.rank, name: trader.name, roi: trader.roi, color: trader.color, avatarPresetId: trader.avatarPresetId)
            }
        }
        .sheet(isPresented: $showJoinLeaderboardSheet, onDismiss: {
            // Immediately sync profile after enrollment — don't wait for debounced observer
            cachedCurrentProfile = SocialService.shared.currentProfile
            cachedLeaderboard = LeaderboardEngine.shared.currentLeaderboard
            // Also re-fetch leaderboard to include the user's new entry
            Task {
                _ = try? await LeaderboardEngine.shared.fetchLeaderboard(
                    category: .pnlPercent,
                    period: .month,
                    tradingMode: localLeaderboardMode,
                    forceRefresh: true
                )
                await MainActor.run {
                    cachedLeaderboard = LeaderboardEngine.shared.currentLeaderboard
                    cachedCurrentProfile = SocialService.shared.currentProfile
                }
            }
        }) {
            JoinLeaderboardSheet()
        }
    }
    
    private var leaderboardButton: some View {
        SectionCTAButton(
            title: "View Full Leaderboard",
            icon: "trophy.fill",
            compact: true
        ) {
            onLeaderboardTapped()
        }
        .padding(.top, 4)
    }
    
    // MARK: - Compact Trader Row
    
    private func compactTraderRow(rank: Int, name: String, roi: Double, color: Color, avatarPresetId: String?) -> some View {
        HStack(spacing: 10) {
            // Rank badge - standardized 22x22
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 22, height: 22)
                
                Text("\(rank)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(color)
            }
            
            // Avatar - using UserAvatarView component
            LeaderboardAvatarView(
                username: name,
                avatarPresetId: avatarPresetId,
                rank: rank,
                size: 28,
                tradingMode: localLeaderboardMode == .paper ? .paper : .portfolio
            )
            
            // Name
            Text("@\(name)")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DS.Adaptive.textPrimary)
                .lineLimit(1)
            
            Spacer()
            
            // ROI
            Text("+\(roi, specifier: "%.1f")%")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.green)
        }
        .padding(.vertical, 4)
    }
    
    /// PERFORMANCE FIX v19: Refresh all cached social snapshots
    private func refreshSocialSnapshots() {
        cachedLeaderboard = LeaderboardEngine.shared.currentLeaderboard
        cachedCurrentProfile = SocialService.shared.currentProfile
        cachedIsPaperTrading = PaperTradingManager.shared.isPaperTradingEnabled
    }
}

// MARK: - Whale Activity Preview Section

/// A preview section for Whale Tracking shown on the Home page
struct WhaleActivityPreviewSection: View {
    // PERFORMANCE FIX v19: Removed @StateObject observation of WhaleTrackingService (10+ @Published)
    // and @ObservedObject of SubscriptionManager (6 @Published).
    // Instead, use @State snapshots updated via debounced onReceive to avoid re-rendering
    // this entire section every time any of the 16+ properties change.
    // PERFORMANCE FIX v21: Removed @EnvironmentObject var appState: AppState
    // AppState has 18+ @Published properties - only dismissHomeSubviews needed, use onReceive.
    var onOpenFullView: () -> Void = {}
    @State private var pulseAnimation: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    
    // Cached snapshots of WhaleTrackingService properties
    @State private var cachedTransactions: [WhaleTransaction] = WhaleTrackingService.shared.recentTransactions
    @State private var cachedStatistics: WhaleStatistics? = WhaleTrackingService.shared.statistics
    @State private var cachedSmartMoneyIndex: SmartMoneyIndex? = WhaleTrackingService.shared.smartMoneyIndex
    @State private var cachedSmartMoneySignals: [SmartMoneySignal] = WhaleTrackingService.shared.smartMoneySignals
    @State private var cachedIsLoading: Bool = WhaleTrackingService.shared.isLoading
    @State private var cachedDataSourceStatus: WhaleTrackingService.DataSourceStatus = WhaleTrackingService.shared.dataSourceStatus
    @State private var cachedIsUsingCachedData: Bool = WhaleTrackingService.shared.isUsingCachedData
    @State private var cachedIsDataStale: Bool = WhaleTrackingService.shared.isDataStale
    @State private var cachedLastDataUpdatedAt: Date? = WhaleTrackingService.shared.lastDataUpdatedAt
    // Cached subscription access
    @State private var cachedHasWhaleAccess: Bool = SubscriptionManager.shared.hasAccess(to: .whaleTracking)
    private let relativeTimeRefreshTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    
    private var isDark: Bool { colorScheme == .dark }
    
    /// Check if user has full whale tracking access (uses cached value)
    private var hasWhaleAccess: Bool { cachedHasWhaleAccess }
    
    /// Convenience accessor (reads cached snapshots, not live service)
    private var service: _WhaleServiceSnapshot {
        _WhaleServiceSnapshot(
            recentTransactions: cachedTransactions,
            statistics: cachedStatistics,
            smartMoneyIndex: cachedSmartMoneyIndex,
            smartMoneySignals: cachedSmartMoneySignals,
            isLoading: cachedIsLoading,
            dataSourceStatus: cachedDataSourceStatus,
            isUsingCachedData: cachedIsUsingCachedData,
            isDataStale: cachedIsDataStale,
            lastDataUpdatedAt: cachedLastDataUpdatedAt
        )
    }
    
    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 10) {
                // Header matching other sections
                sectionHeader
                
                Divider()
                    .background(DS.Adaptive.divider)

                whaleFreshnessMicroLabel
                
                // Exchange Flow Mini Indicator or Volume Summary
                if let stats = service.statistics, stats.totalVolumeUSD > 0 {
                    exchangeFlowIndicator(stats)
                }
                
                // Smart Money Indicator (if available)
                if let smartIndex = service.smartMoneyIndex, !service.smartMoneySignals.isEmpty {
                    smartMoneyMiniIndicator(smartIndex)
                }
                
                // Recent whale transactions preview
                if service.isLoading && service.recentTransactions.isEmpty {
                    skeletonLoadingView
                } else if service.recentTransactions.isEmpty {
                    emptyStateView
                } else {
                    transactionsPreview
                }
                
                // View All Button
                viewAllButton
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
        }
        .onAppear {
            guard AppState.shared.selectedTab == .home else { return }
            // Start monitoring (which fetches data)
            // Service already shows cached data, so UI won't be empty
            WhaleTrackingService.shared.startMonitoring()
            
            // Sync initial snapshots
            refreshSnapshots()
            
            // MEMORY FIX v16: Removed .repeatForever pulse animation
        }
        .onDisappear {
            if AppState.shared.selectedTab != .home {
                WhaleTrackingService.shared.stopMonitoring()
            }
        }
        // PERFORMANCE FIX v19: Debounced observation - only re-render when data actually changes
        // and at most once per 2 seconds (instead of every @Published change)
        .onReceive(
            WhaleTrackingService.shared.objectWillChange
                .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
        ) { _ in
            guard !ScrollStateManager.shared.shouldBlockHeavyOperation() else { return }
            refreshSnapshots()
        }
        .onReceive(
            SubscriptionManager.shared.objectWillChange
                .debounce(for: .seconds(1), scheduler: DispatchQueue.main)
        ) { _ in
            cachedHasWhaleAccess = SubscriptionManager.shared.hasAccess(to: .whaleTracking)
        }
        .onReceive(relativeTimeRefreshTimer) { _ in
            // Keep relative time labels fresh even when transaction data is unchanged.
            refreshSnapshots()
        }
        .onReceive(AppState.shared.$dismissHomeSubviews) { _ in }
    }
    
    // MARK: - Section Header (matching other home sections)
    
    private var sectionHeader: some View {
        HStack {
            HStack(spacing: 8) {
                // Whale icon with gradient background
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.2), Color.cyan.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)
                    
                    Image(systemName: "water.waves")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                Text("Whale Activity")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
            }
            
            Spacer()
            
            // Live indicator badge
            if let stats = service.statistics, stats.totalTransactionsLast24h > 0 {
                liveBadge(stats)
            }
        }
    }
    
    private func liveBadge(_ stats: WhaleStatistics) -> some View {
        let totalFlow = stats.exchangeInflowUSD + stats.exchangeOutflowUSD
        let hasExchangeFlow = totalFlow > 0
        let isBullish = stats.netExchangeFlow < 0
        let sentimentColor: Color = hasExchangeFlow ? (isBullish ? .green : .red) : DS.Adaptive.textTertiary
        
        return HStack(spacing: 6) {
            // Volume badge (clean, no fake percentage)
            if stats.totalVolumeUSD > 0 {
                Text(formatCompactVolume(stats.totalVolumeUSD))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(DS.Adaptive.chipBackground)
                    )
            }
            
            // Transaction count with subtle sentiment indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(sentimentColor)
                    .frame(width: 5, height: 5)
                
                Text("24h: \(stats.totalTransactionsLast24h) tx")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(DS.Adaptive.chipBackground)
            )
        }
    }

    private var whaleFreshnessMicroLabel: some View {
        let freshness: (label: String, color: Color) = {
            if service.isDataStale { return ("Stale cache", .orange) }
            if service.isUsingCachedData { return ("Cached", .yellow) }
            return ("Live", .green)
        }()

        return HStack(spacing: 6) {
            Circle()
                .fill(freshness.color)
                .frame(width: 5, height: 5)

            Text(freshness.label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(freshness.color)

            if let updatedAt = service.lastDataUpdatedAt {
                Text("•")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(DS.Adaptive.textTertiary)

                Text("Updated \(WhaleRelativeTimeFormatter.format(updatedAt))")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }

            Spacer()
        }
    }
    
    private func formatCompactVolume(_ value: Double) -> String {
        let sym = CurrencyManager.symbol
        if value >= 1_000_000_000 {
            return String(format: "%@%.1fB", sym, value / 1_000_000_000)
        } else if value >= 1_000_000 {
            return String(format: "%@%.1fM", sym, value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%@%.0fK", sym, value / 1_000)
        }
        return String(format: "%@%.0f", sym, value)
    }
    
    // MARK: - Exchange Flow Indicator (Compact)
    
    private func exchangeFlowIndicator(_ stats: WhaleStatistics) -> some View {
        let totalFlow = stats.exchangeInflowUSD + stats.exchangeOutflowUSD
        let hasExchangeFlow = totalFlow > 0
        let inflowRatio = hasExchangeFlow ? stats.exchangeInflowUSD / totalFlow : 0.5
        let outflowRatio = hasExchangeFlow ? stats.exchangeOutflowUSD / totalFlow : 0.5
        let isBullish = stats.netExchangeFlow < 0
        
        return VStack(spacing: 6) {
            // Flow bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DS.Adaptive.chipBackground)
                    
                    if hasExchangeFlow {
                        HStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.green)
                                .frame(width: max(geo.size.width * outflowRatio - 1, 0))
                            
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.red)
                                .frame(width: max(geo.size.width * inflowRatio - 1, 0))
                        }
                    } else {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                LinearGradient(
                                    colors: [Color.blue, Color.purple.opacity(0.7)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                }
            }
            .frame(height: 4)
            
            // Labels row
            HStack {
                if hasExchangeFlow {
                    HStack(spacing: 3) {
                        Circle().fill(Color.green).frame(width: 5, height: 5)
                        Text("Out")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 3) {
                        Image(systemName: isBullish ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 8, weight: .bold))
                        Text(isBullish ? "Bullish" : "Bearish")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundColor(isBullish ? .green : .red)
                    
                    Spacer()
                    
                    HStack(spacing: 3) {
                        Text("In")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Circle().fill(Color.red).frame(width: 5, height: 5)
                    }
                } else {
                    Text(formatLargeNumber(stats.totalVolumeUSD) + " volume")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    Spacer()
                    
                    // Show "Active" or "Demo" based on data source status
                    dataStatusBadge
                }
            }
        }
    }
    
    /// Badge showing whether data is live, cached, or stale
    private var dataStatusBadge: some View {
        let (label, color): (String, Color) = {
            if service.isDataStale { return ("Stale", .orange) }
            if service.isUsingCachedData { return ("Cached", .yellow) }
            return ("Live", .blue)
        }()
        
        return HStack(spacing: 3) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 8, weight: .bold))
            Text(label)
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundColor(color)
    }
    
    private func smartMoneyMiniIndicator(_ index: SmartMoneyIndex) -> some View {
        HStack(spacing: 12) {
            // Smart Money icon (institutional/money flow)
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.2), Color.blue.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 24, height: 24)
                
                Image(systemName: "dollarsign.arrow.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Smart Money")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
                
                Text(index.trend.rawValue)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(index.trend.color)
            }
            
            Spacer()
            
            // Mini gauge
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(gaugeColor(for: i, score: index.score))
                        .frame(width: 4, height: 12 + CGFloat(i) * 2)
                }
            }
            
            // Score badge
            Text("\(index.score)")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(index.trend.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(index.trend.color.opacity(0.15))
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.purple.opacity(0.05), Color.blue.opacity(0.03)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.purple.opacity(0.2), Color.blue.opacity(0.1)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 1
                )
        )
    }
    
    private func gaugeColor(for index: Int, score: Int) -> Color {
        let threshold = (index + 1) * 20
        if score >= threshold {
            if score >= 60 {
                return .green
            } else if score >= 40 {
                return .yellow
            } else {
                return .red
            }
        }
        return DS.Adaptive.chipBackground
    }
    
    private var transactionsPreview: some View {
        VStack(spacing: 0) {
            ForEach(Array(service.recentTransactions.prefix(3).enumerated()), id: \.element.id) { index, tx in
                whaleTransactionRow(tx, isFirst: index == 0)
                
                if index < min(service.recentTransactions.count - 1, 2) {
                    Divider()
                        .background(DS.Adaptive.divider)
                }
            }
        }
    }
    
    private func whaleTransactionRow(_ tx: WhaleTransaction, isFirst: Bool = false) -> some View {
        HStack(spacing: 10) {
            // Sentiment color bar
            RoundedRectangle(cornerRadius: 2)
                .fill(tx.sentiment.color)
                .frame(width: 3, height: isFirst ? 40 : 32)
            
            // Blockchain coin logo
            ZStack {
                if tx.isFresh {
                    Circle()
                        .fill(tx.blockchain.color.opacity(0.3))
                        .frame(width: isFirst ? 38 : 28, height: isFirst ? 38 : 28)
                        .scaleEffect(pulseAnimation ? 1.15 : 1.0)
                        .opacity(pulseAnimation ? 0.5 : 0.8)
                }
                
                CoinImageView(symbol: tx.blockchain.symbol, url: nil, size: isFirst ? 32 : 24)
            }
            // SCROLL FIX: Clip pulsing animation to prevent overflow during scroll
            .clipped()
            
            // Amount and type
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(tx.formattedUSD)
                        .font(.system(size: isFirst ? 15 : 13, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    if tx.isFresh {
                        Text("NEW")
                            .font(.system(size: 6, weight: .heavy))
                            .foregroundColor(.white)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.orange))
                    }
                }
                
                HStack(spacing: 3) {
                    Image(systemName: tx.transactionType.icon)
                        .font(.system(size: 7))
                    Text(tx.transactionType.description)
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(tx.sentiment.color.opacity(0.9))
            }
            
            Spacer()
            
            // Time
            VStack(alignment: .trailing, spacing: 2) {
                Text(WhaleRelativeTimeFormatter.format(tx.timestamp))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
                
                if tx.dataSource == .demo {
                    Text("Demo")
                        .font(.system(size: 7, weight: .medium))
                        .foregroundColor(DS.Adaptive.textTertiary.opacity(0.7))
                }
            }
        }
        .padding(.vertical, 6)
    }
    
    // MARK: - Skeleton Loading (Compact design to minimize empty space)
    
    private var skeletonLoadingView: some View {
        HStack(spacing: 12) {
            // Animated loading indicator
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                .scaleEffect(0.8)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Scanning blockchains...")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.Adaptive.textSecondary)
                
                Text("Bitcoin • Ethereum • Solana")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
    
    private var emptyStateView: some View {
        HStack(spacing: 10) {
            Image(systemName: "water.waves")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue.opacity(0.5), .cyan.opacity(0.3)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Monitoring blockchain activity")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.Adaptive.textSecondary)
                
                Text("Transactions $100K+ will appear here (updates every 90s)")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
    
    private var viewAllButton: some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            onOpenFullView()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 12, weight: .semibold))
                Text("Track All Whales")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                
                // Show Pro badge if user doesn't have access
                if !hasWhaleAccess {
                    HStack(spacing: 3) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 8, weight: .bold))
                        Text(StoreKitManager.shared.hasAnyTrialAvailable ? "TRIAL" : "PRO")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundColor(BrandColors.goldBase)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(BrandColors.goldBase.opacity(0.15))
                    )
                }
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(
                LinearGradient(
                    colors: [.blue, .cyan],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.12), Color.cyan.opacity(0.08)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.3), Color.cyan.opacity(0.2)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }
    
    // MARK: - Helpers
    
    private func formatLargeNumber(_ value: Double) -> String {
        let sym = CurrencyManager.symbol
        if value >= 1_000_000_000 {
            return String(format: "%@%.1fB", sym, value / 1_000_000_000)
        } else if value >= 1_000_000 {
            return String(format: "%@%.1fM", sym, value / 1_000_000)
        } else if value >= 1_000 {
            return String(format: "%@%.0fK", sym, value / 1_000)
        }
        return String(format: "%@%.0f", sym, value)
    }
    
    /// PERFORMANCE FIX v19: Refresh cached snapshots from the service
    private func refreshSnapshots() {
        let svc = WhaleTrackingService.shared
        cachedTransactions = svc.recentTransactions
        cachedStatistics = svc.statistics
        cachedSmartMoneyIndex = svc.smartMoneyIndex
        cachedSmartMoneySignals = svc.smartMoneySignals
        cachedIsLoading = svc.isLoading
        cachedDataSourceStatus = svc.dataSourceStatus
        cachedIsUsingCachedData = svc.isUsingCachedData
        cachedIsDataStale = svc.isDataStale
        cachedLastDataUpdatedAt = svc.lastDataUpdatedAt
    }
}

/// PERFORMANCE FIX v19: Lightweight read-only snapshot for WhaleActivityPreviewSection
/// so the body can reference `service.property` syntax without observing the full ObservableObject
struct _WhaleServiceSnapshot {
    let recentTransactions: [WhaleTransaction]
    let statistics: WhaleStatistics?
    let smartMoneyIndex: SmartMoneyIndex?
    let smartMoneySignals: [SmartMoneySignal]
    let isLoading: Bool
    let dataSourceStatus: WhaleTrackingService.DataSourceStatus
    let isUsingCachedData: Bool
    let isDataStale: Bool
    let lastDataUpdatedAt: Date?
}

// MARK: - Notification Extension

extension Notification.Name {
    static let openSocialTab = Notification.Name("OpenSocialTab")
}


