import SwiftUI

private func formatPct(_ frac: Double?) -> String {
    guard let f = frac, f.isFinite else { return "—" }
    let pct = f * 100.0
    return String(format: "%+.2f%%", pct)
}

public struct MarketsCompositeView: View {
    @StateObject private var vm = CompositeMarketViewModel()
    @State private var symbol: String = "BTC"
    @State private var mode: Int = 0 // 0 = Assets (composite), 1 = Pairs

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                header
                Picker("Mode", selection: $mode) {
                    Text("Assets").tag(0)
                    Text("Pairs").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if mode == 0 { compositeSection } else { pairsSection }
                Spacer(minLength: 0)
            }
            .navigationTitle("Markets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { refreshButton } }
            .task { await vm.load(symbol: symbol, force: true) }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            TextField("Symbol", text: $symbol)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .foregroundColor(.primary)
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
            Button("Load") {
                Task { await vm.load(symbol: symbol, force: true) }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal)
    }

    private var refreshButton: some View {
        Button {
            Task { await vm.load(symbol: symbol, force: true) }
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .disabled(vm.isLoading)
    }

    private var compositeSection: some View {
        let up = symbol.uppercased()
        let snap = vm.aggregate[up]
        return Group {
            if let s = snap {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Composite • \(s.method)")
                            .font(.headline)
                        Spacer()
                        Text(formatUSD(s.priceUSD))
                            .font(.headline)
                    }
                    .padding(.horizontal)

                    HStack(spacing: 16) {
                        VStack(alignment: .leading) {
                            Text("1H").font(.caption).foregroundColor(.secondary)
                            Text(formatPct(s.oneHFrac)).foregroundColor((s.oneHFrac ?? 0) >= 0 ? .green : .red)
                        }
                        VStack(alignment: .leading) {
                            Text("24H").font(.caption).foregroundColor(.secondary)
                            Text(formatPct(s.dayFrac)).foregroundColor((s.dayFrac ?? 0) >= 0 ? .green : .red)
                        }
                        VStack(alignment: .leading) {
                            Text("7D").font(.caption).foregroundColor(.secondary)
                            Text(formatPct(s.sevenDFrac)).foregroundColor((s.sevenDFrac ?? 0) >= 0 ? .green : .red)
                        }
                        Spacer()
                    }
                    .padding(.horizontal)

                    // Simple sparkline placeholder using bars
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 2) {
                            ForEach(Array(s.display.enumerated()), id: \.offset) { _, v in
                                Rectangle()
                                    .fill(Color.blue.opacity(0.6))
                                    .frame(width: 2, height: CGFloat(max(1.0, min(80.0, v / max(1e-9, (s.display.max() ?? 1)) * 80.0))))
                            }
                        }
                        .padding(.horizontal)
                        .frame(height: 90)
                    }

                    if !s.constituents.isEmpty {
                        Text("Constituents")
                            .font(.subheadline)
                            .padding(.horizontal)
                        ForEach(0..<s.constituents.count, id: \.self) { i in
                            let c = s.constituents[i]
                            HStack {
                                Text("\(c.pair.exchangeID.uppercased()) • \(c.pair.baseSymbol)-\(c.pair.quoteSymbol)")
                                Spacer()
                                Text(formatUSD(c.priceUSD))
                                Text(String(format: "%.0f%%", c.weight * 100))
                                    .foregroundColor(.secondary)
                            }
                            .font(.footnote)
                            .padding(.horizontal)
                        }
                    }
                }
            } else {
                Text(vm.isLoading ? "Loading…" : "No data")
                    .foregroundColor(.secondary)
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
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                List(rows, id: \.quoteSymbol) { r in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(r.exchangeID.uppercased()) • \(up)-\(r.quoteSymbol)")
                                .font(.subheadline)
                            HStack(spacing: 12) {
                                Text("1H \(formatPct(r.oneHFrac))")
                                    .foregroundColor((r.oneHFrac ?? 0) >= 0 ? .green : .red)
                                Text("24H \(formatPct(r.dayFrac))")
                                    .foregroundColor((r.dayFrac ?? 0) >= 0 ? .green : .red)
                                if let s7 = r.sevenDFrac {
                                    Text("7D \(formatPct(s7))")
                                        .foregroundColor(s7 >= 0 ? .green : .red)
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(formatUSD(r.lastUSD))
                            .font(.headline)
                    }
                }
                .listStyle(.plain)
            }
        }
    }
}

#Preview {
    MarketsCompositeView()
}
