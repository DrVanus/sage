import SwiftUI

struct TechnicalsDetailNativeView: View {
    let symbol: String
    let tvSymbol: String
    let tvTheme: String

    @State private var selectedInterval: ChartInterval = .oneDay
    @StateObject private var vm = TechnicalsViewModel()

    // Keep intervals simple and supported by our data fetcher
    private let intervals: [ChartInterval] = [.oneHour, .fourHour, .oneDay, .oneWeek, .oneMonth]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header row: title + TradingView link
                HStack {
                    Text("Technicals for \(symbol)")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    NavigationLink {
                        TechnicalsDetailView(symbol: tvSymbol, theme: tvTheme)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chart.xyaxis.line")
                            Text("Open in TradingView")
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                // Timeframe chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(intervals, id: \.self) { intv in
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { selectedInterval = intv }
                                vm.refresh(symbol: symbol, interval: intv, currentPrice: 0)
                            } label: {
                                Text(intv.rawValue)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(selectedInterval == intv ? .black : .white)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .background(
                                        Capsule().fill(selectedInterval == intv ? Color.white.opacity(0.9) : Color.white.opacity(0.06))
                                    )
                                    .overlay(
                                        Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                }

                // Gauge card
                VStack(alignment: .center, spacing: 12) {
                    TechnicalsGaugeView(summary: vm.summary, timeframeLabel: selectedInterval.rawValue)
                        .frame(maxWidth: .infinity)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

                if let err = vm.errorMessage {
                    Text(err)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .padding(.top, 4)
                }

                Spacer(minLength: 12)
            }
            .padding(16)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationTitle("Technicals")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .center) {
            if vm.isLoading {
                ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white))
            }
        }
        .onAppear {
            vm.refresh(symbol: symbol, interval: selectedInterval, currentPrice: 0)
        }
    }
}
