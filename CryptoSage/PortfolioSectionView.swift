import SwiftUI

struct PortfolioHeaderView: View {
    @EnvironmentObject var vm: HomeViewModel
    @Binding var selectedRange: HomeView.PortfolioRange

    let onNotifications: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                // Left: Portfolio Metrics
                VStack(alignment: .leading, spacing: 4) {
                    Text("Portfolio Value")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Text(vm.portfolioValueString)
                        .font(.title2)
                        .bold()
                    if let sparklineData = vm.portfolioSparklineData, !sparklineData.isEmpty {
                        HomeLineChart(data: sparklineData)
                            .frame(height: 30)
                            .padding(.top, 4)
                    }
                }
                Spacer()
                // Right: Buttons
                VStack(spacing: 8) {
                    HStack(spacing: 14) {
                        Button(action: onNotifications) {
                            Image(systemName: "bell")
                                .font(.title3)
                        }
                        Button(action: onSettings) {
                            Image(systemName: "gearshape")
                                .font(.title3)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            // Horizontal Chips Scroll
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(HomeView.PortfolioRange.allCases, id: \.self) { range in
                        let isSelected = range == selectedRange
                        Text(range.rawValue)
                            .font(.footnote)
                            .fontWeight(isSelected ? .semibold : .regular)
                            .foregroundColor(isSelected ? .primary : .secondary)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                            )
                            .onTapGesture {
                                selectedRange = range
                            }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
}
