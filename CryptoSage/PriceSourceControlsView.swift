import SwiftUI
import Combine

struct KnownExchanges {
    static let all: [(id: String, name: String)] = [
        ("binance", "Binance"),
        ("coinbase", "Coinbase")
    ]
}

enum PriceSourcePreference: String, CaseIterable, Identifiable {
    case auto
    case ws
    case manager
    case gecko

    var id: String { rawValue }
}

class AppSettings {
    private static let priceSourceKey = "PriceSourcePreference"
    private static let compositeAllowedExchangesKey = "CompositeAllowedExchanges"
    private static let preferredExchangePrefix = "PreferredExchangeForAsset_"

    static var priceSourcePreference: PriceSourcePreference {
        get {
            if let raw = UserDefaults.standard.string(forKey: priceSourceKey),
               let pref = PriceSourcePreference(rawValue: raw) {
                return pref
            }
            return .auto
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: priceSourceKey)
        }
    }

    static func compositeAllowedExchanges() -> [String]? {
        UserDefaults.standard.stringArray(forKey: compositeAllowedExchangesKey)
    }

    static func setCompositeAllowedExchanges(_ exchanges: [String]?) {
        UserDefaults.standard.set(exchanges, forKey: compositeAllowedExchangesKey)
    }

    static func preferredExchange(for symbol: String) -> String? {
        UserDefaults.standard.string(forKey: preferredExchangePrefix + symbol.uppercased())
    }

    static func setPreferredExchange(for symbol: String, exchangeID: String?) {
        let key = preferredExchangePrefix + symbol.uppercased()
        if let exchangeID = exchangeID {
            UserDefaults.standard.set(exchangeID, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
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
                        ForEach(PriceSourcePreference.allCases) { pref in
                            Text(pref.rawValue.capitalized).tag(pref)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedPref) { newValue in
                        AppSettings.priceSourcePreference = newValue
                        onChanged?()
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
                selectedPref = AppSettings.priceSourcePreference
                if let ids = AppSettings.compositeAllowedExchanges() {
                    allowed = Set(ids)
                } else {
                    allowed.removeAll()
                }
                preferredExchangeForAsset = AppSettings.preferredExchange(for: symbol)
            }
            .padding(.vertical, 4)
        }
    }
}

#Preview {
    StatefulPreviewWrapper("BTC") { sym in
        PriceSourceControlsView(symbol: sym)
            .padding()
    }
}

// Helper to preview @Binding
struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State private var value: Value
    var content: (Binding<Value>) -> Content

    init(_ initialValue: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: initialValue)
        self.content = content
    }

    var body: some View { content($value) }
}
