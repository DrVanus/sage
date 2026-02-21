import SwiftUI

struct MarketPairsSheet: View {
    let symbol: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = CompositeMarketViewModel()
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @State private var mode: Int = 0 // 0 = Composite, 1 = Pairs, 2 = Arbitrage
    @State private var showArbitragePaywall = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Mode", selection: $mode) {
                    Text("Composite").tag(0)
                    Text("Exchanges").tag(1)
                    Text("Arbitrage").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                switch mode {
                case 0: compositeSection
                case 1: pairsSection
                case 2:
                    if subscriptionManager.hasAccess(to: .arbitrageScanner) {
                        arbitrageSection
                    } else {
                        arbitrageLockedView
                    }
                default: compositeSection
                }

                Spacer(minLength: 0)
            }
            .navigationTitle("\(symbol.uppercased()) Markets")
            .navigationBarTitleDisplayMode(.inline)
            .unifiedPaywallSheet(feature: .arbitrageScanner, isPresented: $showArbitragePaywall)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    CSNavButton(icon: "xmark", action: { dismiss() }, accessibilityText: "Close", compact: true)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await vm.load(symbol: symbol, force: true) } } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DS.Adaptive.gold)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(DS.Adaptive.chipBackground))
                            .overlay(Circle().stroke(DS.Adaptive.stroke, lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.isLoading)
                }
            }
            .toolbarBackground(DS.Adaptive.background, for: .navigationBar)
            .task { await vm.load(symbol: symbol, force: true) }
        }
    }
    
    // MARK: - Arbitrage Locked View
    private var arbitrageLockedView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "lock.fill")
                .font(.system(size: 40))
                .foregroundStyle(DS.Adaptive.gold)
            Text("Arbitrage Scanner")
                .font(.title3.weight(.bold))
                .foregroundColor(DS.Adaptive.textPrimary)
            Text("Spot price differences across exchanges and find profitable arbitrage opportunities.")
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showArbitragePaywall = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "crown.fill")
                    Text("Unlock Arbitrage Scanner")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(
                PremiumPrimaryCTAStyle(
                    height: 50,
                    horizontalPadding: 16,
                    cornerRadius: 14,
                    font: .headline
                )
            )
            .padding(.horizontal, 32)
            Spacer()
        }
    }
    
    // MARK: - Arbitrage Section
    private var arbitrageSection: some View {
        let up = symbol.uppercased()
        let rows = vm.pairs[up] ?? []
        
        return Group {
            if rows.count < 2 {
                VStack(spacing: 12) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(vm.isLoading ? "Loading exchange data…" : "Need 2+ exchanges for arbitrage")
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                let sorted = rows.sorted { $0.lastUSD < $1.lastUSD }
                let lowestPrice = sorted.first!
                let highestPrice = sorted.last!
                let spread = highestPrice.lastUSD - lowestPrice.lastUSD
                let spreadPct = (spread / lowestPrice.lastUSD) * 100
                
                VStack(alignment: .leading, spacing: 16) {
                    // Arbitrage opportunity card
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: spreadPct >= 0.5 ? "bolt.fill" : "equal.circle")
                                .foregroundStyle(spreadPct >= 0.5 ? .yellow : .secondary)
                            Text(spreadPct >= 0.5 ? "Arbitrage Opportunity" : "Prices Aligned")
                                .font(.headline)
                            Spacer()
                            Text(String(format: "%.2f%% spread", spreadPct))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(spreadPct >= 0.5 ? .green : .secondary)
                        }
                        
                        Divider()
                        
                        // Buy low
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("BUY LOW")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.green)
                                HStack(spacing: 4) {
                                    exchangeBadge(lowestPrice.exchangeID)
                                    Text(lowestPrice.exchangeID.uppercased())
                                        .font(.subheadline.weight(.medium))
                                }
                            }
                            Spacer()
                            Text(formatUSD(lowestPrice.lastUSD))
                                .font(.title3.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.green)
                        }
                        
                        // Arrow
                        HStack {
                            Spacer()
                            Image(systemName: "arrow.down")
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        
                        // Sell high
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("SELL HIGH")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.red)
                                HStack(spacing: 4) {
                                    exchangeBadge(highestPrice.exchangeID)
                                    Text(highestPrice.exchangeID.uppercased())
                                        .font(.subheadline.weight(.medium))
                                }
                            }
                            Spacer()
                            Text(formatUSD(highestPrice.lastUSD))
                                .font(.title3.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.red)
                        }
                        
                        Divider()
                        
                        // Profit calculation
                        HStack {
                            Text("Potential Profit (1 unit):")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(formatUSD(spread))
                                .font(.headline)
                                .monospacedDigit()
                                .foregroundStyle(spreadPct >= 0.5 ? .green : .primary)
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray6))
                    )
                    .padding(.horizontal)
                    
                    // All exchange prices ranked
                    Text("All Exchange Prices")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal)
                    
                    ForEach(Array(sorted.enumerated()), id: \.offset) { index, row in
                        HStack {
                            Text("\(index + 1).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            
                            exchangeBadge(row.exchangeID)
                            
                            Text(row.exchangeID.uppercased())
                                .font(.subheadline)
                            
                            Text("• \(row.quoteSymbol)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                            
                            let diffFromLow = ((row.lastUSD - lowestPrice.lastUSD) / lowestPrice.lastUSD) * 100
                            if index > 0 {
                                Text(String(format: "+%.2f%%", diffFromLow))
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            
                            Text(formatUSD(row.lastUSD))
                                .font(.subheadline.weight(.medium))
                                .monospacedDigit()
                        }
                        .padding(.horizontal)
                    }
                }
            }
        }
    }
    
    // Exchange badge with color coding
    private func exchangeBadge(_ exchangeID: String) -> some View {
        let color: Color = {
            switch exchangeID.lowercased() {
            case "binance": return .yellow
            case "coinbase": return .blue
            case "kraken": return .purple
            case "kucoin": return .green
            default: return .gray
            }
        }()
        
        return Circle()
            .fill(color)
            .frame(width: 8, height: 8)
    }

    private var compositeSection: some View {
        let up = symbol.uppercased()
        let snap = vm.aggregate[up]
        return Group {
            if let s = snap {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Method • \(s.method)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatUSD(s.priceUSD))
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                    }
                    .padding(.horizontal)

                    HStack(spacing: 16) {
                        metric("1H", s.oneHFrac)
                        metric("24H", s.dayFrac)
                        metric("7D", s.sevenDFrac)
                        Spacer()
                    }
                    .padding(.horizontal)

                    if !s.constituents.isEmpty {
                        Text("Constituents")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal)
                        ForEach(0..<s.constituents.count, id: \.self) { i in
                            let c = s.constituents[i]
                            HStack {
                                Text("\(c.pair.exchangeID.uppercased()) • \(c.pair.baseSymbol)-\(c.pair.quoteSymbol)")
                                Spacer()
                                Text(String(format: "%.0f%%", c.weight * 100))
                                    .foregroundStyle(.secondary)
                            }
                            .font(.footnote)
                            .padding(.horizontal)
                        }
                    }
                }
            } else {
                Text(vm.isLoading ? "Loading…" : "No data")
                    .foregroundStyle(.secondary)
                    .padding()
            }
        }
    }

    private var pairsSection: some View {
        let up = symbol.uppercased()
        let rows = vm.pairs[up] ?? []
        return Group {
            if rows.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "building.columns")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(vm.isLoading ? "Loading exchanges…" : "No trading pairs found")
                        .foregroundStyle(.secondary)
                }
                .padding()
            } else {
                // Group by exchange
                let grouped = Dictionary(grouping: rows) { $0.exchangeID }
                let exchangeOrder = ["binance", "coinbase", "kraken", "kucoin"]
                let sortedExchanges = grouped.keys.sorted { a, b in
                    let aIdx = exchangeOrder.firstIndex(of: a.lowercased()) ?? 999
                    let bIdx = exchangeOrder.firstIndex(of: b.lowercased()) ?? 999
                    return aIdx < bIdx
                }
                
                ScrollView {
                    VStack(spacing: 16) {
                        // Exchange count summary
                        HStack(spacing: 12) {
                            ForEach(sortedExchanges, id: \.self) { exchange in
                                HStack(spacing: 4) {
                                    exchangeBadge(exchange)
                                    Text(exchange.uppercased())
                                        .font(.caption.weight(.medium))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(Color(.systemGray5))
                                )
                            }
                            Spacer()
                        }
                        .padding(.horizontal)
                        
                        // Pairs by exchange
                        ForEach(sortedExchanges, id: \.self) { exchange in
                            if let pairs = grouped[exchange] {
                                VStack(alignment: .leading, spacing: 8) {
                                    // Exchange header
                                    HStack {
                                        exchangeBadge(exchange)
                                        Text(exchange.uppercased())
                                            .font(.subheadline.weight(.semibold))
                                        Text("• \(pairs.count) pair\(pairs.count == 1 ? "" : "s")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                    }
                                    .padding(.horizontal)
                                    
                                    // Pairs for this exchange
                                    ForEach(pairs, id: \.quoteSymbol) { r in
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("\(up)/\(r.quoteSymbol)")
                                                    .font(.subheadline.weight(.medium))
                                                HStack(spacing: 8) {
                                                    changeChip("1H", r.oneHFrac)
                                                    changeChip("24H", r.dayFrac)
                                                    if let s7 = r.sevenDFrac {
                                                        changeChip("7D", s7)
                                                    }
                                                }
                                            }
                                            Spacer()
                                            Text(formatUSD(r.lastUSD))
                                                .font(.headline)
                                                .monospacedDigit()
                                        }
                                        .padding(.horizontal)
                                        .padding(.vertical, 8)
                                        .background(Color(.systemGray6).opacity(0.5))
                                        .cornerRadius(8)
                                        .padding(.horizontal)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
    }
    
    // Compact change chip
    private func changeChip(_ label: String, _ frac: Double?) -> some View {
        let value = frac ?? 0
        let isPositive = value >= 0
        return HStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(formatPct(frac))
                .font(.caption2.weight(.medium))
                .foregroundStyle(isPositive ? .green : .red)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill((isPositive ? Color.green : Color.red).opacity(0.15))
        )
    }

    private func metric(_ title: String, _ frac: Double?) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(formatPct(frac)).foregroundStyle((frac ?? 0) >= 0 ? .green : .red)
        }
    }
}

private func formatPct(_ frac: Double?) -> String {
    guard let f = frac, f.isFinite else { return "—" }
    let pct = f * 100.0
    return String(format: "%+.2f%%", pct)
}

// Note: formatUSD is defined in TradeView.swift and available module-wide

#Preview {
    MarketPairsSheet(symbol: "BTC")
}
