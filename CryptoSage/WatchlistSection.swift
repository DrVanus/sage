import SwiftUI

// MARK: - AnimatedPriceText
/// Displays the coin’s price with a color flash and a temporary tick icon
/// whenever the price changes. The tick icon (an arrow in a circle) appears
/// briefly to indicate whether the price went up or down.
struct AnimatedPriceText: View {
    let price: Double

    // Store old price locally for comparison
    @State private var oldPrice: Double = 0.0
    // Current text color
    @State private var textColor: Color = .white
    // Temporary tick icon (e.g., "arrow.up.circle.fill" or "arrow.down.circle.fill")
    @State private var tickIcon: String? = nil

    var body: some View {
        HStack(spacing: 2) {
            Text(formatPrice(price))
                .foregroundColor(textColor.opacity(0.7))
                .font(.footnote)
            if let icon = tickIcon {
                Image(systemName: icon)
                    .foregroundColor(textColor.opacity(0.7))
                    .font(.footnote)
            }
        }
        .onAppear {
            oldPrice = price
        }
        .onChange(of: price) { newPrice in
            guard newPrice != oldPrice else { return }
            // Flash color and icon
            withAnimation(.easeIn(duration: 0.2)) {
                if newPrice > oldPrice {
                    textColor = .green
                    tickIcon = "arrow.up.circle.fill"
                } else {
                    textColor = .red
                    tickIcon = "arrow.down.circle.fill"
                }
            }
            // Revert after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeOut(duration: 0.5)) {
                    textColor = .white
                    tickIcon = nil
                }
            }
            oldPrice = newPrice
        }
    }

    /// Formats a price value into a currency string.
    private func formatPrice(_ value: Double) -> String {
        guard value > 0 else { return "$0.00" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        if value < 1.0 {
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 8
        } else {
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
        }
        return "$" + (formatter.string(from: NSNumber(value: value)) ?? "0.00")
    }
}

// MARK: - ChangeView
struct ChangeView: View {
    let label: String
    let change: Double

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))
            Text(change >= 0
                ? "▲\(String(format: "%.2f%%", change))"
                : "▼\(String(format: "%.2f%%", abs(change)))")
                .font(.caption2)
                .monospacedDigit()
                .foregroundColor(change >= 0 ? .green : .red)
        }
        .frame(width: 80, alignment: .trailing)
    }
}

// MARK: - WatchlistSection
struct WatchlistSection: View {
    @EnvironmentObject var marketVM: MarketViewModel
    @State private var isLoadingWatchlist = false

    // Local state for "Show More / Show Less"
    @State private var showAll = false

    // Timer to auto-refresh watchlist data (every 15 seconds)
    @State private var refreshTimer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    // Coins in user’s watchlist (fetched by IDs)
    private var liveWatchlist: [MarketCoin] {
        marketVM.watchlistCoins
    }

    // How many coins to show when collapsed
    private let maxVisible = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "eye")
                        .foregroundColor(.yellow)
                    Text("Your Watchlist")
                        .font(.title3).bold()
                        .foregroundColor(.white)
                }
                Spacer()
            }
            Divider()
                .background(Color.white.opacity(0.15))

            if liveWatchlist.isEmpty {
                emptyWatchlistView
            } else {
                let coinsToShow = showAll ? liveWatchlist : Array(liveWatchlist.prefix(maxVisible))
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.white.opacity(0.03))
                    VStack(spacing: 0) {
                        ForEach(coinsToShow, id: \.id) { coin in
                            rowContent(for: coin)
                                .frame(height: 45)
                        }
                    }
                    .frame(height: CGFloat(coinsToShow.count) * 45)
                    .animation(.easeInOut, value: showAll)
                    .cornerRadius(8)
                }
                .frame(maxWidth: .infinity)

                if liveWatchlist.count > maxVisible {
                    Button {
                        withAnimation(.spring()) {
                            showAll.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(showAll ? "Show Less" : "Show More")
                                .font(.callout)
                                .foregroundColor(.white)
                            Image(systemName: showAll ? "chevron.up" : "chevron.down")
                                .foregroundColor(.white)
                                .font(.footnote)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .onReceive(refreshTimer) { _ in
            Task {
                isLoadingWatchlist = true
                defer { isLoadingWatchlist = false }
                do {
                    try await marketVM.loadWatchlistData()
                } catch {
                    print("Failed to load watchlist:", error)
                }
            }
        }
        .onAppear {
            Task {
                isLoadingWatchlist = true
                defer { isLoadingWatchlist = false }
                do {
                    try await marketVM.loadWatchlistData()
                } catch {
                    print("Failed to load watchlist:", error)
                }
            }
        }
    }

    // MARK: - Empty Watchlist View
    private var emptyWatchlistView: some View {
        VStack(spacing: 16) {
            Text("No coins in your watchlist yet.")
                .font(.callout)
                .foregroundColor(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.05))
        )
    }

    // MARK: - Row Content
    private func rowContent(for coin: MarketCoin) -> some View {
        HStack(spacing: 8) {
            // Left accent bar (gold gradient)
            Rectangle()
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.yellow, Color.orange]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 4)

            // Coin icon and basic info
            CoinImageView(symbol: coin.symbol, url: coin.imageUrl, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(coin.symbol.uppercased())
                    .font(.subheadline)
                    .foregroundColor(.white)
                // Price with animated flash and tick icon on the right
                AnimatedPriceText(price: coin.priceUsd ?? 0)
            }
            Spacer()
            // 1H and 24H percentage changes with arrow icons
            HStack(spacing: 16) {
                ChangeView(label: "1H:", change: coin.priceChangePercentage1hInCurrency ?? 0)
                ChangeView(label: "24H:", change: coin.priceChangePercentage24hInCurrency ?? 0)
            }
            .font(.caption2)
            .animation(.easeInOut, value: coin.priceChangePercentage1hInCurrency)
            .animation(.easeInOut, value: coin.priceChangePercentage24hInCurrency)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.clear)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                marketVM.toggleFavorite(coin)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    // MARK: - Helpers (Formatting and Image)
    private func sectionHeading(_ text: String, iconName: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let icon = iconName {
                    Image(systemName: icon)
                        .foregroundColor(.yellow)
                }
                Text(text)
                    .font(.title3).bold()
                    .foregroundColor(.white)
            }
            Divider()
                .background(Color.white.opacity(0.15))
        }
    }
}
