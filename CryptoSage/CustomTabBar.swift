import SwiftUI

fileprivate enum TabBarColors {
    // Dark mode: bright gold gradient (looks great on dark background)
    static let selectedGradientDark: LinearGradient = LinearGradient(
        colors: [BrandColors.goldLight, BrandColors.goldBase],
        startPoint: .top,
        endPoint: .bottom
    )
    
    // Light mode: brand gold gradient — goldBase → goldDark for rich, legible gold on light backgrounds
    static let selectedGradientLight: LinearGradient = LinearGradient(
        colors: [BrandColors.goldBase, BrandColors.goldDark],
        startPoint: .top,
        endPoint: .bottom
    )
    
    // Solid colors for the underline indicator
    static let indicatorDark: Color = BrandColors.goldBase
    static let indicatorLight: Color = BrandColors.goldBase
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
    // PERFORMANCE FIX v22: Removed @EnvironmentObject AppState.
    // AppState has 18+ @Published properties (tab, keyboard, 5 nav paths, etc.).
    // CustomTabBar only WRITES to AppState (pop-to-root on double-tap) — it never reads
    // AppState properties in body. Yet the observation caused tab bar re-renders on every
    // keyboard show/hide, every nav path change, every tab switch — ~50+ times per session.
    // Using AppState.shared for write-only access breaks the observation chain.
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var haptics = UISelectionFeedbackGenerator()
    @State private var lastTapTime: TimeInterval = 0
    
    private var isDark: Bool { colorScheme == .dark }
    
    // Adaptive selected gradient - bright gold in both modes for brand consistency
    private var selectedGradient: LinearGradient {
        isDark ? TabBarColors.selectedGradientDark : TabBarColors.selectedGradientLight
    }
    
    // Adaptive indicator color
    private var indicatorColor: LinearGradient {
        LinearGradient(
            colors: [isDark ? TabBarColors.indicatorDark : TabBarColors.indicatorLight],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

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
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        // Compact tab bar height (52pt) - closer to Apple's standard
        .frame(height: 52, alignment: .top)
        // LAYOUT STABILITY: Ensure consistent background
        .background(DS.Adaptive.background)
        .overlay(
            Rectangle()
                .frame(height: 0.5)  // Thin separator line
                .foregroundColor(DS.Adaptive.stroke.opacity(0.5)),
            alignment: .top
        )
        .compositingGroup() // PERFORMANCE: Flatten view hierarchy for faster rendering
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { haptics.prepare() }
    }
    
    @ViewBuilder
    private func tabItem(_ tab: CustomTab,
                         isSelected: Bool,
                         selectedImage: String,
                         normalImage: String,
                         title: String) -> some View {
        Button(action: {
            // PERFORMANCE: Minimal debounce (50ms) to prevent double-taps
            let now = CACurrentMediaTime()
            if now - lastTapTime < 0.05 { return }
            lastTapTime = now
            
            // Fire haptics immediately
            haptics.selectionChanged()
            
            if selectedTab == tab {
                // Pop to root for the current tab - execute immediately
                switch tab {
                case .home:
                    AppState.shared.homeNavPath = NavigationPath()
                    AppState.shared.dismissHomeSubviews = true
                case .market:
                    AppState.shared.marketNavPath = NavigationPath()
                    AppState.shared.dismissMarketSubviews = true
                case .trade:
                    AppState.shared.tradeNavPath = NavigationPath()
                case .portfolio:
                    AppState.shared.portfolioNavPath = NavigationPath()
                    AppState.shared.dismissPortfolioSubviews = true
                case .ai:
                    AppState.shared.aiNavPath = NavigationPath()
                }
            } else {
                // PERFORMANCE: Direct assignment - no animation wrapper
                selectedTab = tab
            }
            
            // Prepare haptics for next tap (background)
            Task { @MainActor in haptics.prepare() }
        }) {
            tabItemContent(
                isSelected: isSelected,
                selectedImage: selectedImage,
                normalImage: normalImage,
                title: title
            )
        }
        .buttonStyle(TabButtonStyle())  // PERFORMANCE FIX: Custom button style for instant response
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
        
        VStack(spacing: 2) {
            // Top padding
            Spacer()
                .frame(height: 6)
            
            // Icon with adaptive gradient when selected, secondary color when not
            Group {
                if isSelected {
                    Image(systemName: iconName)
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(selectedGradient)
                } else {
                    Image(systemName: iconName)
                        .symbolRenderingMode(.monochrome)
                        .foregroundColor(.secondary)
                }
            }
            .font(.system(size: 22, weight: isSelected ? .semibold : .medium))
            .frame(height: 24)
            
            // Text label with adaptive gradient when selected
            Group {
                if isSelected {
                    Text(title)
                        .foregroundStyle(selectedGradient)
                } else {
                    Text(title)
                        .foregroundColor(.secondary)
                }
            }
            .font(.system(size: 10, weight: .semibold))
            .fixedSize(horizontal: true, vertical: true)
            .frame(height: 12)
            
            // Underline indicator for selected tab
            Capsule()
                .fill(indicatorColor)
                .frame(width: isSelected ? 18 : 0, height: 2)
                .opacity(isSelected ? 1 : 0)
            
            // Bottom space
            Spacer()
                .frame(height: 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .contentShape(Rectangle())
        // PERFORMANCE FIX: Disable all animations on tab item content for instant response
        .transaction { $0.animation = nil }
    }
}

// Custom button style for instant visual feedback - no animations
private struct TabButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .transaction { $0.animation = nil }
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
