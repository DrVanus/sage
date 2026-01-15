import SwiftUI

fileprivate enum BrandGold {
    static let light = BrandColors.goldLight
    static let dark  = BrandColors.goldBase
    static let horizontalGradient: LinearGradient = BrandColors.goldHorizontal
}

enum CustomTab: String, Hashable {
    case home = "home"
    case market = "market"
    case trade = "trade"
    case portfolio = "portfolio"
    case ai = "ai"
}

struct CustomTabBar: View {
    @Binding var selectedTab: CustomTab
    @EnvironmentObject var appState: AppState
    
    @State private var haptics = UISelectionFeedbackGenerator()
    @State private var lastTapTime: TimeInterval = 0

    var body: some View {
        HStack(spacing: 0) {
            tabItem(.home,
                    isSelected: selectedTab == .home,
                    selectedImage: "house.circle.fill", normalImage: "house.circle",
                    title: "Home")
            tabItem(.market,
                    isSelected: selectedTab == .market,
                    selectedImage: "chart.line.uptrend.xyaxis", normalImage: "chart.line.downtrend.xyaxis",
                    title: "Market")
            tabItem(.trade,
                    isSelected: selectedTab == .trade,
                    selectedImage: "arrow.left.arrow.right.circle.fill", normalImage: "arrow.left.arrow.right.circle",
                    title: "Trading")
            tabItem(.portfolio,
                    isSelected: selectedTab == .portfolio,
                    selectedImage: "chart.pie.fill", normalImage: "chart.pie",
                    title: "Portfolio")
            tabItem(.ai,
                    isSelected: selectedTab == .ai,
                    selectedImage: "bubble.left.and.bubble.right.fill", normalImage: "bubble.left.and.bubble.right",
                    title: "AI Chat")
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background(Color(UIColor.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.gray.opacity(0.3)),
            alignment: .top
        )
        // Removed .drawingGroup(opaque: false) - causes expensive GPU compositing on every frame
        .onAppear { haptics.prepare() }
    }
    
    @ViewBuilder
    private func tabItem(_ tab: CustomTab,
                         isSelected: Bool,
                         selectedImage: String,
                         normalImage: String,
                         title: String) -> some View {
        Button(action: {
            // Debounce rapid taps to avoid double state churn
            let now = CACurrentMediaTime()
            if now - lastTapTime < 0.15 { return }
            lastTapTime = now
            haptics.selectionChanged()
            haptics.prepare()
            
            if selectedTab == tab {
                // Pop to root for the current tab
                switch tab {
                case .home:
                    appState.homeNavPath = NavigationPath()
                    // Trigger dismissal of legacy NavigationLink-based subviews
                    appState.dismissHomeSubviews = true
                case .market: appState.marketNavPath = NavigationPath()
                case .trade: appState.tradeNavPath = NavigationPath()
                case .portfolio: appState.portfolioNavPath = NavigationPath()
                case .ai: appState.aiNavPath = NavigationPath()
                }
            } else {
                selectedTab = tab
            }
        }) {
            tabItemContent(
                isSelected: isSelected,
                selectedImage: selectedImage,
                normalImage: normalImage,
                title: title
            )
        }
        .buttonStyle(.plain)
        .id(tab)
        .accessibilityLabel(title)
        .accessibilityHint("Switch to \(title) tab")
    }
    
    @ViewBuilder
    private func tabItemContent(
        isSelected: Bool,
        selectedImage: String,
        normalImage: String,
        title: String
    ) -> some View {
        let iconName = isSelected ? selectedImage : normalImage
        
        VStack(spacing: 4) {
            // Icon with gold gradient when selected, secondary color when not
            // Using Group to handle the gradient vs color styling cleanly
            Group {
                if isSelected {
                    Image(systemName: iconName)
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(BrandGold.horizontalGradient)
                } else {
                    Image(systemName: iconName)
                        .symbolRenderingMode(.monochrome)
                        .foregroundColor(.secondary)
                }
            }
            .font(.system(size: 22, weight: .semibold))
            .frame(height: 24)
            .animation(.none, value: isSelected) // Prevent interpolation delay
            
            // Text label with gold gradient when selected
            Group {
                if isSelected {
                    Text(title)
                        .foregroundStyle(BrandGold.horizontalGradient)
                } else {
                    Text(title)
                        .foregroundColor(.secondary)
                }
            }
            .font(.system(size: 10, weight: .medium))
            .fixedSize(horizontal: true, vertical: true)
            .frame(height: 12)
            .animation(.none, value: isSelected) // Prevent interpolation delay
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .contentShape(Rectangle())
    }
}

struct CustomTabBar_Previews: PreviewProvider {
    @State static var selectedTab: CustomTab = .home
    
    static var previews: some View {
        CustomTabBar(selectedTab: $selectedTab)
            .previewLayout(.sizeThatFits)
            .background(Color.gray)
    }
}
