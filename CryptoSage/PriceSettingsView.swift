import SwiftUI

struct PriceSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSource: PriceSourcePreference = AppSettings.priceSourcePreference
    @State private var allowedExchangesText: String = AppSettings.compositeAllowedExchanges()?.joined(separator: ",") ?? ""

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Live Price Source")) {
                    Picker("Source", selection: $selectedSource) {
                        Text("Auto").tag(PriceSourcePreference.auto)
                        Text("WebSocket (Binance)").tag(PriceSourcePreference.ws)
                        Text("Manager (App Overlay)").tag(PriceSourcePreference.manager)
                        Text("CoinGecko (Polling)").tag(PriceSourcePreference.gecko)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedSource) { _, newValue in
                        // Defer to avoid "Modifying state during view update"
                        DispatchQueue.main.async { AppSettings.priceSourcePreference = newValue }
                    }
                    Text(helpText(for: selectedSource))
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }

                Section(header: Text("Composite Price Exchanges"), footer: Text("Comma-separated exchange IDs. Leave blank to allow all configured exchanges.")) {
                    TextField("e.g. binance,coinbase,kraken", text: $allowedExchangesText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    HStack {
                        Button("Save") {
                            let ids = parseIDs(allowedExchangesText)
                            AppSettings.setCompositeAllowedExchanges(ids)
                        }
                        Spacer()
                        Button("Clear") {
                            allowedExchangesText = ""
                            AppSettings.setCompositeAllowedExchanges(nil)
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Price Settings")
            .enableInteractivePopGesture()
            .edgeSwipeToDismiss(onDismiss: { dismiss() })
        }
        .navigationViewStyle(.stack)
    }

    private func parseIDs(_ text: String) -> [String]? {
        let tokens = text
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        return tokens.isEmpty ? nil : tokens
    }

    private func helpText(for pref: PriceSourcePreference) -> String {
        switch pref {
        case .auto:
            return "Auto arbitrates between WS, Manager, and CoinGecko with smoothing and cooldowns."
        case .ws:
            return "Use Binance WebSocket fast ticks when available (falls back on cooldown)."
        case .manager:
            return "Use app-wide overlay prices from LivePriceManager (polling + overlays)."
        case .gecko:
            return "Use CoinGecko polling only (slowest, most conservative)."
        }
    }
}

#Preview {
    PriceSettingsView()
}
