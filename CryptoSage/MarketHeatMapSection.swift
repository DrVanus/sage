import SwiftUI

#if !USE_HOME_SHIMS

public struct MarketHeatMapSection: View {
    @EnvironmentObject var homeVM: HomeViewModel
    @State private var timeframe: HeatMapTimeframe = .day1
    @State private var showAllList: Bool = false

    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            TimeframeChipRow(timeframe: $timeframe)

            GridHeatMapView(
                tiles: homeVM.heatMapVM.tiles,
                timeframe: timeframe,
                onShowAll: { showAllList = true }
            )
            .frame(height: 240)

            LegendView(bound: bound(for: timeframe))
                .padding(.horizontal)
        }
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
        )
        .sheet(isPresented: $showAllList) {
            AllCoinsListSheet(
                tiles: homeVM.heatMapVM.tiles,
                timeframe: timeframe,
                lastUpdated: homeVM.heatMapVM.lastUpdated,
                onSelect: { _ in }
            )
        }
    }

    struct TimeframeChipRow: View {
        @Binding var timeframe: HeatMapTimeframe

        private let options: [(title: String, value: HeatMapTimeframe)] = [
            ("1h", .hour1),
            ("24h", .day1),
            ("7d", .week1)
        ]

        var body: some View {
            HStack(spacing: 12) {
                ForEach(options, id: \.value) { option in
                    Button {
                        timeframe = option.value
                    } label: {
                        Text(option.title)
                            .font(.footnote)
                            .foregroundColor(timeframe == option.value ? .white : .primary.opacity(0.7))
                            .padding(.vertical, 6)
                            .padding(.horizontal, 14)
                            .background(
                                Capsule()
                                    .fill(timeframe == option.value ? Color.accentColor : Color.clear)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
}

#endif
