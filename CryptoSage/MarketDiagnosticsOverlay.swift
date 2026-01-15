import SwiftUI

struct MarketDiagnosticsOverlay: View {
    @ObservedObject var vm: MarketViewModel
    @State private var limit: Int = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Market Diagnostics")
                    .font(.headline)
                Spacer()
                Button(vm.enableDiagLogs ? "Logs: ON" : "Logs: OFF") {
                    vm.setDiagnosticsLoggingEnabled(!vm.enableDiagLogs)
                }
                .font(.caption)
                .padding(6)
                .background(Color.blue.opacity(0.15))
                .cornerRadius(6)
            }
            .padding(.bottom, 4)

            HStack(spacing: 12) {
                Text("Rows: \(limit)")
                    .font(.caption)
                Slider(value: Binding(get: { Double(limit) }, set: { limit = Int($0) }), in: 5...50, step: 1)
            }
            .padding(.bottom, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(vm.diagnosticsForWatchlist().prefix(limit)) { entry in
                        DiagnosticsRow(entry: entry)
                            .padding(6)
                            .background(Color.black.opacity(0.04))
                            .cornerRadius(6)
                    }
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .padding()
    }
}

private struct DiagnosticsRow: View {
    let entry: MarketViewModel.DiagnosticsEntry

    private func fmt(_ v: Double?) -> String {
        guard let x = v, x.isFinite else { return "—" }
        if abs(x) >= 1000 { return String(format: "%.0f", x) }
        if abs(x) >= 100 { return String(format: "%.1f", x) }
        if abs(x) >= 1 { return String(format: "%.2f", x) }
        return String(format: "%.4f", x)
    }
    private func fmtPct(_ v: Double?) -> String {
        guard let x = v, x.isFinite else { return "—" }
        return String(format: "%+.2f%%", x)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(entry.symbol)")
                    .font(.subheadline).bold()
                Spacer()
                Text("id: \(entry.id)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Group {
                    Text("spot: \(fmt(entry.spot))")
                    Text("lastSpark: \(fmt(entry.lastSpark))")
                    Text("Δ: \(fmt(entry.deltaToSpark))")
                }.font(.caption)
            }
            HStack(spacing: 12) {
                Group {
                    Text("drv1h: \(fmtPct(entry.derived1h))")
                    Text("drv24h: \(fmtPct(entry.derived24h))")
                }.font(.caption)
                Spacer(minLength: 8)
                Group {
                    Text("prov1h: \(fmtPct(entry.provider1h))")
                    Text("prov24h: \(fmtPct(entry.provider24h))")
                }.font(.caption)
                Spacer(minLength: 8)
                Group {
                    Text("snap1h: \(fmtPct(entry.snapshot1h))")
                    Text("snap24h: \(fmtPct(entry.snapshot24h))")
                }.font(.caption)
            }
        }
    }
}

#Preview {
    MarketDiagnosticsOverlay(vm: MarketViewModel.shared)
}
