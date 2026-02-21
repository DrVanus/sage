import SwiftUI

struct MarketDiagnosticsOverlay: View {
    @ObservedObject var vm: MarketViewModel
    @State private var limit: Int = 20
    @State private var logsEnabled: Bool = false
    
    @MainActor
    private var staleSuppressionSummary: String? {
        guard let m = LivePriceManager.shared.staleSuppressionMetricsSnapshot() else { return nil }
        return "Suppressed stale (\(m.windowSec)s): total=\(m.total) | sidecar 1h/24h/7d=\(m.sidecar1h)/\(m.sidecar24h)/\(m.sidecar7d) | sidecar vol=\(m.sidecarVolume) | blocked provider 24h/vol=\(m.provider24hBlocked)/\(m.providerVolumeBlocked)"
    }
    
    @MainActor
    private var stalenessAlertSummary: String? {
        guard let alert = LivePriceManager.shared.lastDataStalenessAlert else { return nil }
        let ageSec = max(0, Int(Date().timeIntervalSince(alert.timestamp)))
        guard ageSec <= 10 * 60 else { return nil } // only show recent alerts
        let fsSync = alert.lastFirestoreSyncAgeSec.map { "\($0)s" } ?? "n/a"
        return "Stale flow alert (\(ageSec)s ago): reason=\(alert.reason), fallbackCount=\(alert.recentOverlayFallbackCount), lastFirestoreSync=\(fsSync)"
    }

    @MainActor
    private func buildEntries() -> [DiagEntry] {
        let coins = vm.watchlistCoins.isEmpty ? vm.allCoins : vm.watchlistCoins
        return coins.map { c in
            let spot = c.priceUsd
            let lastSpark = c.sparklineIn7d.last
            let delta: Double? = {
                if let s = spot, let l = lastSpark, s.isFinite, l.isFinite, l > 0 { return (s - l) / l * 100.0 }
                return nil
            }()
            let d1 = LivePriceManager.shared.bestChange1hPercent(for: c.symbol)
            let d24 = LivePriceManager.shared.bestChange24hPercent(for: c.symbol)
            let freshness = LivePriceManager.shared.sidecarFreshness(for: c.symbol)
            return DiagEntry(
                id: c.id,
                symbol: c.symbol.uppercased(),
                spot: spot,
                lastSpark: lastSpark,
                deltaToSpark: delta,
                derived1h: d1,
                derived24h: d24,
                provider1h: c.priceChangePercentage1hInCurrency,
                provider24h: c.priceChangePercentage24hInCurrency,
                snapshot1h: nil,
                snapshot24h: nil,
                age1hSec: freshness.percent1hAgeSec,
                age24hSec: freshness.percent24hAgeSec,
                age7dSec: freshness.percent7dAgeSec,
                ageVolSec: freshness.volumeAgeSec
            )
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Market Diagnostics")
                    .font(.headline)
                Spacer()
                Button(logsEnabled ? "Logs: ON" : "Logs: OFF") {
                    logsEnabled.toggle()
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
            
            if let staleAlert = stalenessAlertSummary {
                Text(staleAlert)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.12))
                    .cornerRadius(6)
            }
            
            if let staleSuppressionSummary {
                Text(staleSuppressionSummary)
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.yellow.opacity(0.12))
                    .cornerRadius(6)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(buildEntries().prefix(limit))) { entry in
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
        .onAppear {
            LivePriceManager.shared.setPercentDebugLogging(logsEnabled)
        }
        .onChange(of: logsEnabled) { _, enabled in
            LivePriceManager.shared.setPercentDebugLogging(enabled)
        }
    }
}

private struct DiagEntry: Identifiable {
    let id: String
    let symbol: String
    let spot: Double?
    let lastSpark: Double?
    let deltaToSpark: Double?
    let derived1h: Double?
    let derived24h: Double?
    let provider1h: Double?
    let provider24h: Double?
    let snapshot1h: Double?
    let snapshot24h: Double?
    let age1hSec: Int?
    let age24hSec: Int?
    let age7dSec: Int?
    let ageVolSec: Int?
}

private struct DiagnosticsRow: View {
    let entry: DiagEntry

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
    private func fmtAge(_ sec: Int?) -> String {
        guard let sec else { return "—" }
        return "\(sec)s"
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
            HStack(spacing: 12) {
                Group {
                    Text("age1h: \(fmtAge(entry.age1hSec))")
                    Text("age24h: \(fmtAge(entry.age24hSec))")
                    Text("age7d: \(fmtAge(entry.age7dSec))")
                    Text("ageVol: \(fmtAge(entry.ageVolSec))")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    MarketDiagnosticsOverlay(vm: MarketViewModel.shared)
}
