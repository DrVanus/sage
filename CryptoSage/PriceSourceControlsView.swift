import SwiftUI
import Combine

struct KnownExchanges {
    static let all: [(id: String, name: String)] = [
        ("binance", "Binance"),
        ("coinbase", "Coinbase")
    ]
}

struct PriceSourceControlsView: View {
    @Binding var symbol: String
    var onChanged: (() -> Void)? = nil

    @State private var selectedPref: PriceSourcePreference = .auto
    @State private var allowed: Set<String> = []
    @State private var preferredExchangeForAsset: String? = nil

    var body: some View {
        GroupBox("Price Source & Exchanges") {
            VStack(alignment: .leading, spacing: 12) {
                // Price source preference
                VStack(alignment: .leading, spacing: 6) {
                    Text("Live Price Source").font(.footnote).foregroundStyle(.secondary)
                    Picker("Source", selection: $selectedPref) {
                        Text("Auto").tag(PriceSourcePreference.auto)
                        Text("WS").tag(PriceSourcePreference.ws)
                        Text("Manager").tag(PriceSourcePreference.manager)
                        Text("Gecko").tag(PriceSourcePreference.gecko)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedPref) { _, newValue in
                        // Defer to avoid "Modifying state during view update"
                        DispatchQueue.main.async {
                            AppSettings.priceSourcePreference = newValue
                            onChanged?()
                        }
                    }
                }

                Divider().padding(.vertical, 2)

                // Per-asset preferred exchange
                VStack(alignment: .leading, spacing: 6) {
                    Text("Preferred Exchange for \(symbol.uppercased())").font(.footnote).foregroundStyle(.secondary)
                    Picker("Preferred Exchange", selection: Binding<String?>(
                        get: { preferredExchangeForAsset },
                        set: { newVal in
                            preferredExchangeForAsset = newVal
                            AppSettings.setPreferredExchange(for: symbol, exchangeID: newVal)
                            onChanged?()
                        })
                    ) {
                        Text("Automatic").tag(String?.none)
                        ForEach(KnownExchanges.all, id: \.id) { item in
                            Text(item.name).tag(String?.some(item.id))
                        }
                    }
                    .pickerStyle(.menu)
                }

                Divider().padding(.vertical, 2)

                // Composite allowed exchanges multi-select
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Composite Exchanges").font(.footnote).foregroundStyle(.secondary)
                        Spacer()
                        Button("Reset") {
                            allowed.removeAll()
                            AppSettings.setCompositeAllowedExchanges(nil)
                            onChanged?()
                        }
                        .buttonStyle(.borderless)
                    }
                    ForEach(KnownExchanges.all, id: \.id) { item in
                        Button(action: {
                            if allowed.contains(item.id) { allowed.remove(item.id) } else { allowed.insert(item.id) }
                            let arr = allowed.isEmpty ? nil : Array(allowed)
                            AppSettings.setCompositeAllowedExchanges(arr)
                            onChanged?()
                        }) {
                            HStack {
                                Image(systemName: allowed.contains(item.id) ? "checkmark.square.fill" : "square")
                                Text(item.name)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .onAppear {
                // Defer to avoid "Modifying state during view update"
                DispatchQueue.main.async {
                    selectedPref = AppSettings.priceSourcePreference
                    if let ids = AppSettings.compositeAllowedExchanges() { allowed = Set(ids) } else { allowed.removeAll() }
                    preferredExchangeForAsset = AppSettings.preferredExchange(for: symbol)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

#Preview {
    PriceSourceControlsView_PreviewContainer()
}

private struct PriceSourceControlsView_PreviewContainer: View {
    @State private var symbol: String = "BTC"

    var body: some View {
        PriceSourceControlsView(symbol: $symbol)
            .padding()
    }
}
