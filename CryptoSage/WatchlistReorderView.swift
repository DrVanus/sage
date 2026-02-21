import SwiftUI

struct WatchlistReorderView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var favorites = FavoritesManager.shared
    @EnvironmentObject private var marketVM: MarketViewModel

    @State private var order: [String] = [] // coin IDs in order

    var body: some View {
        NavigationStack {
            List {
                ForEach(order, id: \.self) { id in
                    HStack(spacing: 10) {
                        if let coin = coin(for: id) {
                            CoinImageView(symbol: coin.symbol, url: coin.imageUrl, size: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(coin.symbol.uppercased())
                                    .font(.subheadline).bold().foregroundColor(.white)
                                Text(coin.name)
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                        } else {
                            Text(id).foregroundColor(.white)
                        }
                        Spacer()
                        Image(systemName: "line.3.horizontal")
                            .foregroundColor(.secondary)
                    }
                    .listRowBackground(Color.black)
                }
                .onMove(perform: move)
            }
            .environment(\.editMode, .constant(.active)) // always show drag handles
            .scrollContentBackground(.hidden)
            .background(Color.black)
            .navigationTitle("Reorder Watchlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    CSNavButton(icon: "xmark", action: { dismiss() }, accessibilityText: "Close", compact: true)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { applyAndDismiss() } label: {
                        Text("Done")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(DS.Adaptive.gold)
                    }
                }
            }
            .toolbarBackground(DS.Adaptive.background, for: .navigationBar)
            .onAppear {
                // Defer to avoid "Modifying state during view update"
                DispatchQueue.main.async {
                    // Seed with current order filtered to existing favorites
                    let favs = Array(favorites.favoriteIDs)
                    let current = favorites.getOrder()
                    // Build order: current order first, then any new favs not yet in order
                    var seen = Set<String>()
                    var out: [String] = []
                    for id in current where favs.contains(id) { if !seen.contains(id) { out.append(id); seen.insert(id) } }
                    for id in favs where !seen.contains(id) { out.append(id); seen.insert(id) }
                    self.order = out
                }
            }
        }
        .tint(.yellow)
    }

    private func coin(for id: String) -> MarketCoin? {
        return marketVM.allCoins.first(where: { $0.id == id })
            ?? marketVM.lastGoodAllCoins.first(where: { $0.id == id })
    }

    private func move(from: IndexSet, to: Int) {
        order.move(fromOffsets: from, toOffset: to)
    }

    private func applyAndDismiss() {
        FavoritesManager.shared.updateOrder(order)
        dismiss()
    }
}

#Preview {
    WatchlistReorderView()
        .environmentObject(MarketViewModel.shared)
}
