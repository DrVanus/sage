import SwiftUI

struct MarketView: View {
    @StateObject private var vm = MarketViewModel()

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {

                    // Segmented filter row & search toggle
                    segmentRow

                    // Search bar
                    if vm.showSearchBar {
                        TextField("Search coins...", text: $vm.searchText)
                            .foregroundColor(.white)
                            .onChange(of: vm.searchText) { oldValue, newValue in
                                vm.applyAllFiltersAndSort()
                            }
                            .padding(8)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(8)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                    }

                    // Table column headers
                    columnHeader

                    // Always display the coin list
                    coinList
                }
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            vm.selectedSegment = .all
            Task {
                await vm.loadAllData()
                await vm.loadWatchlistData()
                vm.applyAllFiltersAndSort()
                vm.setupLivePriceUpdates()
            }
        }
    }

    // MARK: - Subviews

    private var segmentRow: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(MarketSegment.allCases, id: \.self) { seg in
                        Button {
                            vm.updateSegment(seg)
                            vm.applyAllFiltersAndSort()
                        } label: {
                            Text(seg.rawValue)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(vm.selectedSegment == seg ? .black : .white)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .background(vm.selectedSegment == seg ? Color.white : Color.white.opacity(0.1))
                                .cornerRadius(16)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            Button {
                withAnimation { vm.showSearchBar.toggle() }
            } label: {
                Image(systemName: vm.showSearchBar ? "magnifyingglass.circle.fill" : "magnifyingglass.circle")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(.trailing, 16)
            }
        }
        .background(Color.black)
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            headerButton("Coin", .coin)
                .frame(width: 140, alignment: .leading)
            Text("7D")
                .font(.caption)
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 40, alignment: .center)
            headerButton("Price", .price)
                .frame(width: 70, alignment: .trailing)
            headerButton("24h", .dailyChange)
                .frame(width: 50, alignment: .trailing)
            headerButton("Vol", .volume)
                .frame(width: 70, alignment: .trailing)
            Text("Fav")
                .font(.caption)
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 40, alignment: .center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.05))
    }

    private var coinList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 0) {
                ForEach(vm.coins, id: \.id) { coin in
                    NavigationLink(destination: CoinDetailView(coin: coin)) {
                        CoinRowView(coin: coin)
                            .padding(.vertical, 8)
                            .padding(.horizontal)
                    }
                    .buttonStyle(PlainButtonStyle())

                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.leading, 16)
                }
            }
            .padding(.bottom, 12)
        }
        .refreshable {
            vm.manualRefresh()
        }
    }

    // MARK: - Helpers

    private func headerButton(_ label: String, _ field: SortField) -> some View {
        Button {
            vm.toggleSort(for: field)
            vm.applyAllFiltersAndSort()
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.9))
                if vm.sortField == field {
                    Image(systemName: vm.sortDirection == .asc ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .background(vm.sortField == field ? Color.white.opacity(0.05) : Color.clear)
    }
}

#if DEBUG
struct MarketView_Previews: PreviewProvider {
    static var marketVM = MarketViewModel.shared
    static var previews: some View {
        MarketView()
            .environmentObject(marketVM)
    }
}
#endif
