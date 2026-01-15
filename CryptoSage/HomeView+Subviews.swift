//
//  HomeView+Subviews.swift
//  CryptoSage
//
//  Extracted Home subviews to resolve duplication and compile issues.
//

import SwiftUI

extension HomeView {

    // AI & Invite Section
    var aiAndInviteSection: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "exclamationmark.shield").foregroundColor(.green)
                    Text("AI Risk Scan").font(.headline).foregroundStyle(.white)
                }
                Text("Quickly analyze your portfolio risk.")
                    .font(.caption)
                    .foregroundStyle(.gray)
                Button("Scan Now") {}
                    .buttonStyle(CSGoldButtonStyle())
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)).shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "gift").foregroundColor(.yellow)
                    Text("Invite & Earn BTC").font(.headline).foregroundStyle(.white)
                }
                Text("Refer friends, get rewards.")
                    .font(.caption)
                    .foregroundStyle(.gray)
                Button("Invite Now") {}
                    .buttonStyle(CSGoldButtonStyle())
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)).shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2))
        }
    }

    // Trending Section
    var trendingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(text: "Trending", iconName: "flame")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(marketVM.trendingCoins) { coin in
                        CoinCardView(coin: coin)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)).shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2))
    }

    // Top Movers Section
    var topMoversSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(text: "Top Gainers", iconName: "arrow.up.right")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(marketVM.topGainers) { coin in
                        CoinCardView(coin: coin)
                    }
                }
                .padding(.vertical, 6)
            }

            SectionHeading(text: "Top Losers", iconName: "arrow.down.right")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(marketVM.topLosers) { coin in
                        CoinCardView(coin: coin)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)).shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2))
    }

    // Arbitrage Section (placeholder; we will enhance in a later pass)
    var arbitrageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(text: "Arbitrage Opportunities", iconName: "arrow.left.and.right.circle")
            Text("Find price differences across exchanges for potential profit.")
                .font(.caption)
                .foregroundStyle(.gray)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("BTC/USDT").foregroundStyle(.white)
                    Text("Ex A: $65,000\nEx B: $66,200\nPotential: $1,200")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("ETH/USDT").foregroundStyle(.white)
                    Text("Ex A: $1,800\nEx B: $1,805\nProfit: $5")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)).shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2))
    }

    // Explore Section
    var exploreSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(text: "Explore", iconName: "magnifyingglass")
            Text("Discover advanced AI and market features.")
                .font(.caption)
                .foregroundStyle(.gray)
            HStack(spacing: 12) {
                exploreChip(title: "AI Market Scan", icon: "waveform.path.ecg", subtitle: "Scan signals") { }
                exploreChip(title: "DeFi Analytics", icon: "chart.bar.doc.horizontal", subtitle: "Monitor yields") { }
                exploreChip(title: "NFT Explorer", icon: "sparkles.rectangle.stack.fill", subtitle: "Trending collections") { }
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)).shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2))
    }

    func exploreChip(title: String, icon: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.gray)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
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
    }

    enum TxFilter: String, CaseIterable { case all = "All", buys = "Buys", sells = "Sells", transfers = "Transfers", staking = "Staking" }

    final class RecentTransactionsViewModel: ObservableObject {
        @Published var isLoading = false
        @Published var items: [RecentTransaction] = [
            RecentTransaction(symbol: "BTC", title: "Buy BTC", subtitle: "Coinbase • Network fee $0.42", cryptoAmountSigned: "+0.012 BTC", fiatAmount: "$350", direction: .in, status: .completed, hash: "0x9c3…a1f2", date: Date().addingTimeInterval(-60*60*3)),
            RecentTransaction(symbol: "ETH", title: "Sell ETH", subtitle: "Binance • Limit order", cryptoAmountSigned: "-0.05 ETH", fiatAmount: "$90", direction: .out, status: .completed, hash: "0x1ab…9d2e", date: Date().addingTimeInterval(-60*60*24)),
            RecentTransaction(symbol: "SOL", title: "Stake SOL", subtitle: "Marinade • APY 7.1%", cryptoAmountSigned: "+10 SOL", fiatAmount: "", direction: .in, status: .pending, hash: nil, date: Date().addingTimeInterval(-60*60*24*2))
        ]

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
        var body: some View {
            ZStack {
                Circle().fill(Color.white.opacity(0.12))
                Text(String(symbol.prefix(3)))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 28, height: 28)
        }
    }

    struct RecentTransactionRow: View {
        let tx: RecentTransaction
        @State private var expanded = false

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    TokenIcon(symbol: tx.symbol)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(tx.title).font(.headline).foregroundStyle(.white)
                            if let status = tx.status {
                                Text(status.rawValue)
                                    .font(.caption2)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(badgeColor(for: status))
                                    .clipShape(Capsule())
                                    .accessibilityLabel("Status: \(status.rawValue)")
                            }
                        }
                        Text(tx.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(tx.cryptoAmountSigned)
                            .font(.headline)
                            .foregroundStyle(tx.direction == .out ? .red : .green)
                        if !tx.fiatAmount.isEmpty {
                            Text(tx.fiatAmount).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Text(relativeTime(from: tx.date))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if expanded {
                    VStack(alignment: .leading, spacing: 6) {
                        if let hash = tx.hash { Text("Tx Hash: \(hash)").font(.caption).textSelection(.enabled) }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.snappy) { expanded.toggle(); haptic(.light) } }
            .swipeActions(edge: .trailing) {
                Button("Repeat") { haptic(.medium) }.tint(.blue)
                Button("Share") { haptic(.rigid) }.tint(.gray)
            }
            .padding(.vertical, 4)
        }

        private func badgeColor(for status: TxStatus) -> Color {
            switch status {
            case .pending: return .yellow.opacity(0.2)
            case .failed: return .red.opacity(0.2)
            case .completed: return .green.opacity(0.2)
            }
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
    }

    struct RecentTransactionsSection: View {
        @State private var filter: TxFilter = .all
        @StateObject private var vm = RecentTransactionsViewModel()

        var body: some View {
            VStack(spacing: 12) {
                SectionHeading(text: "Recent Transactions", iconName: "clock.arrow.circlepath")
                    .padding(.horizontal, 16)

                Picker("", selection: $filter) {
                    ForEach(TxFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                LazyVStack(spacing: 8) {
                    ForEach(vm.transactions(filteredBy: filter)) { tx in
                        RecentTransactionRow(tx: tx)
                            .padding(.horizontal, 16)
                    }
                }
                .redacted(reason: vm.isLoading ? .placeholder : [])
                .padding(.bottom, 8)
            }
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)).shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2))
            .padding(.horizontal, 16)
        }
    }

    var transactionsSection: some View { RecentTransactionsSection() }

    var communitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(text: "Community", iconName: "person.3")
            Text("Join the discussion with other traders.")
                .font(.caption)
                .foregroundStyle(.gray)
            HStack(spacing: 12) {
                Button { } label: {
                    Label("Open Forum", systemImage: "bubble.left.and.bubble.right")
                        .font(.subheadline.weight(.semibold))
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)

                Button { } label: {
                    Label("Discord", systemImage: "bolt.horizontal.circle")
                        .font(.subheadline.weight(.semibold))
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.05)).shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2))
    }

    var footer: some View {
        VStack(spacing: 8) {
            Divider().background(Color.white.opacity(0.15))
            Text("CryptoSage • Experimental build").font(.footnote).foregroundStyle(.secondary)
            Text("This is not financial advice.").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}
