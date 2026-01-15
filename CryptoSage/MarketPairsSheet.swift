import SwiftUI

struct MarketPairsSheet: View {
    let symbol: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var vm = CompositeMarketViewModel()
    @State private var mode: Int = 0 // 0 = Composite, 1 = Pairs

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("Mode", selection: $mode) {
                    Text("Composite").tag(0)
                    Text("Pairs").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if mode == 0 { compositeSection } else { pairsSection }

                Spacer(minLength: 0)
            }
            .navigationTitle("\(symbol.uppercased()) Markets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await vm.load(symbol: symbol, force: true) } } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(vm.isLoading)
                }
            }
            .task { await vm.load(symbol: symbol, force: true) }
        }
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
                Text(vm.isLoading ? "Loading…" : "No pairs")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                List(rows, id: \.quoteSymbol) { r in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(r.exchangeID.uppercased()) • \(up)-\(r.quoteSymbol)")
                                .font(.subheadline)
                            HStack(spacing: 12) {
                                Text("1H \(formatPct(r.oneHFrac))")
                                    .foregroundStyle((r.oneHFrac ?? 0) >= 0 ? .green : .red)
                                Text("24H \(formatPct(r.dayFrac))")
                                    .foregroundStyle((r.dayFrac ?? 0) >= 0 ? .green : .red)
                                if let s7 = r.sevenDFrac {
                                    Text("7D \(formatPct(s7))")
                                        .foregroundStyle(s7 >= 0 ? .green : .red)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(formatUSD(r.lastUSD))
                            .font(.headline)
                            .monospacedDigit()
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func metric(_ title: String, _ frac: Double?) -> some View {
        VStack(alignment: .leading) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(formatPct(frac)).foregroundStyle((frac ?? 0) >= 0 ? .green : .red)
        }
    }
}

private func formatUSD(_ v: Double) -> String {
    guard v.isFinite, v > 0 else { return "$0.00" }
    let nf = NumberFormatter()
    nf.numberStyle = .currency
    nf.currencyCode = "USD"
    nf.maximumFractionDigits = (v < 1.0) ? 8 : 2
    nf.minimumFractionDigits = (v < 1.0) ? 2 : 2
    return nf.string(from: NSNumber(value: v)) ?? "$0.00"
}

private func formatPct(_ frac: Double?) -> String {
    guard let f = frac, f.isFinite else { return "—" }
    let pct = f * 100.0
    return String(format: "%+.2f%%", pct)
}

#Preview {
    MarketPairsSheet(symbol: "BTC")
}
