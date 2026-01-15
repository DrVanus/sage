import SwiftUI

/// A shared, brand-styled "Source" menu used by both the Technicals page and the Coin page.
/// It renders a pill label ("Source · <Display>") and a menu with checkmarks for the selected source.
/// The component hides itself if it determines there's no displayable source label (e.g., "No data").
struct TechnicalsSourceMenu: View {
    let sourceLabel: String
    let preferred: TechnicalsViewModel.TechnicalsSourcePreference
    let onSelect: (TechnicalsViewModel.TechnicalsSourcePreference) -> Void

    private func displaySourceLabel(_ source: String) -> String {
        let lower = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Hide explicit 'no data'
        if lower.contains("no data") { return "" }
        var base: String = source.trimmingCharacters(in: .whitespacesAndNewlines)
        // Map any of these to CryptoSage AI
        if lower.isEmpty
            || lower == "auto"
            || lower.contains("memory")
            || lower.contains("cache")
            || lower.contains("cached")
            || lower.contains("internal")
            || lower.contains("sparkline")
            || lower.contains("on-device")
            || lower.contains("on device")
            || lower.contains("derived")
            || lower.contains("local")
            || lower.contains("offline")
            || lower.contains("cash") {
            base = "CryptoSage AI"
        } else if lower.contains("coingecko") {
            base = "CoinGecko"
        } else if lower.contains("coinbase") {
            base = "Coinbase"
        } else if lower.contains("binance") {
            base = "Binance"
        }
        // Strip explicit ' • fallback' noise
        if let range = base.range(of: "• fallback", options: [.caseInsensitive]) {
            base.removeSubrange(range)
            base = base.trimmingCharacters(in: .whitespaces)
        }
        // Preserve stale suffix if present on original
        if lower.contains("stale") && !base.lowercased().contains("stale") {
            base += " • stale"
        }
        return base
    }

    @ViewBuilder
    var body: some View {
        let display = displaySourceLabel(sourceLabel)
        if !display.isEmpty {
            Menu {
                Button(action: { onSelect(.auto) }) {
                    HStack { if preferred == .auto { Image(systemName: "checkmark") }; Text("CryptoSage AI") }
                }
                Button(action: { onSelect(.coinGecko) }) {
                    HStack { if preferred == .coinGecko { Image(systemName: "checkmark") }; Text("CoinGecko") }
                }
                Button(action: { onSelect(.coinbase) }) {
                    HStack { if preferred == .coinbase { Image(systemName: "checkmark") }; Text("Coinbase") }
                }
                Button(action: { onSelect(.binance) }) {
                    HStack { if preferred == .binance { Image(systemName: "checkmark") }; Text("Binance") }
                }
            } label: {
                SharedSourceMenuLabel(sourceRaw: sourceLabel, displayText: display)
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .transaction { txn in txn.animation = nil } // avoid any implicit flashing
        } else {
            EmptyView()
        }
    }
}

private struct SharedSourceMenuLabel: View {
    let sourceRaw: String
    let displayText: String
    var body: some View {
        HStack(spacing: 6) {
            if sourceRaw.lowercased().contains("stale") {
                Circle().fill(Color.orange).frame(width: 6, height: 6)
            }
            Text("Source")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.white.opacity(0.75))
            if !displayText.isEmpty {
                Text("· \(displayText)")
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
                    .lineLimit(1)
            }
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.white.opacity(0.6))
                .padding(.leading, 2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.6)
        )
    }
}
