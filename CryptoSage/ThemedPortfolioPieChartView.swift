import SwiftUI
import Charts

#if DEBUG
import Combine

/// A dummy PriceService for SwiftUI previews
private struct PreviewPriceService: PriceService {
    func pricePublisher(for symbols: [String], interval: TimeInterval) -> AnyPublisher<[String: Double], Never> {
        Just([:]).eraseToAnyPublisher()
    }
}
#endif

/// A donut (pie) chart view that displays each coin’s share of the portfolio
/// based on its current value (quantity * currentPrice).
struct ThemedPortfolioPieChartView: View {
    @ObservedObject var portfolioVM: PortfolioViewModel
    @Binding var showLegend: Bool
    @State private var selectedSlice: PortfolioViewModel.AllocationSlice? = nil

    /// Initialize with optional legend binding (defaults to false).
    init(
        portfolioVM: PortfolioViewModel,
        showLegend: Binding<Bool> = .constant(false)
    ) {
        self.portfolioVM = portfolioVM
        self._showLegend = showLegend
    }

    var body: some View {
        if #available(iOS 16.0, *) {
            Chart(portfolioVM.allocationData, id: \.symbol) { slice in
                SectorMark(
                    angle: .value("Percent", slice.percent),
                    innerRadius: .ratio(0.5),
                    outerRadius: .ratio(0.85)
                )
                .foregroundStyle(slice.color)
            }
            .chartLegend(showLegend ? .visible : .hidden)
            .chartLegend(position: .bottom, alignment: .center, spacing: 8)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                let localPoint = CGPoint(
                                    x: value.location.x - geo.frame(in: .local).origin.x,
                                    y: value.location.y - geo.frame(in: .local).origin.y
                                )
                                if let result = proxy.value(at: localPoint, as: (String, Double).self) {
                                    let symbol = result.0
                                    if let tappedSlice = portfolioVM.allocationData.first(where: { $0.symbol == symbol }) {
                                        selectedSlice = tappedSlice
                                    }
                                }
                            }
                        )
                }
            }
            .frame(maxHeight: 140)
            .overlay(alignment: .center) {
                if let slice = selectedSlice {
                    VStack(spacing: 4) {
                        Text(slice.symbol)
                            .font(.caption)
                            .foregroundColor(.white)
                        Text(String(format: "%.0f%%", slice.percent))
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.75)))
                    .onTapGesture { selectedSlice = nil }
                }
            }
        } else {
            Text("Pie chart requires iOS 16+.")
                .foregroundColor(.gray)
        }
    }
}

struct ThemedPortfolioPieChartView_Previews: PreviewProvider {
    static var previews: some View {
        // Create a preview repository and VM
        let manualService = ManualPortfolioDataService(initialHoldings: [], initialTransactions: [])
        let liveService   = LivePortfolioDataService()
#if DEBUG
        let priceService  = PreviewPriceService()
#else
        let priceService  = CoinPaprikaData()
#endif
        let repo = PortfolioRepository(
            manualService: manualService,
            liveService:   liveService,
            priceService:  priceService
        )
        let vm = PortfolioViewModel(repository: repo)
        return ThemedPortfolioPieChartView(
            portfolioVM: vm,
            showLegend: .constant(false)
        )
        .frame(width: 200, height: 200)
    }
}
