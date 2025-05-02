import SwiftUI

enum CustomTab {
    case home, market, trade, portfolio, ai
}

struct CustomTabBar: View {
    @Binding var selectedTab: CustomTab
    
    var body: some View {
        HStack {
            
            // HOME
            Button(action: {
                selectedTab = .home
            }) {
                VStack(spacing: 2) {
                    Image(systemName: selectedTab == .home ? "house.circle.fill" : "house.circle")
                        .resizable()
                        .frame(width: 24, height: 24)
                    Text("Home")
                        .font(.caption)
                }
                .scaleEffect(selectedTab == .home ? 1.1 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selectedTab)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .foregroundColor(selectedTab == .home ? Color.yellow : Color.secondary)
            
            Spacer()
            
            // MARKET
            Button(action: {
                selectedTab = .market
            }) {
                VStack(spacing: 2) {
                    Image(systemName: selectedTab == .market ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis")
                        .resizable()
                        .frame(width: 24, height: 24)
                    Text("Market")
                        .font(.caption)
                }
                .scaleEffect(selectedTab == .market ? 1.1 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selectedTab)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .foregroundColor(selectedTab == .market ? Color.yellow : Color.secondary)
            
            Spacer()
            
            // TRADE
            Button(action: {
                selectedTab = .trade
            }) {
                VStack(spacing: 2) {
                    Image(systemName: selectedTab == .trade ? "arrow.left.arrow.right.circle.fill" : "arrow.left.arrow.right.circle")
                        .resizable()
                        .frame(width: 24, height: 24)
                    Text("Trading")
                        .font(.caption)
                }
                .scaleEffect(selectedTab == .trade ? 1.1 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selectedTab)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .foregroundColor(selectedTab == .trade ? Color.yellow : Color.secondary)
            
            Spacer()
            
            // PORTFOLIO
            Button(action: {
                selectedTab = .portfolio
            }) {
                VStack(spacing: 2) {
                    Image(systemName: selectedTab == .portfolio ? "chart.pie.fill" : "chart.pie")
                        .resizable()
                        .frame(width: 24, height: 24)
                    Text("Portfolio")
                        .font(.caption)
                }
                .scaleEffect(selectedTab == .portfolio ? 1.1 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selectedTab)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .foregroundColor(selectedTab == .portfolio ? Color.yellow : Color.secondary)
            
            Spacer()
            
            // AI CHAT
            Button(action: {
                selectedTab = .ai
            }) {
                VStack(spacing: 2) {
                    Image(systemName: selectedTab == .ai ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                        .resizable()
                        .frame(width: 24, height: 24)
                    Text("AI Chat")
                        .font(.caption)
                }
                .scaleEffect(selectedTab == .ai ? 1.1 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: selectedTab)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .foregroundColor(selectedTab == .ai ? Color.yellow : Color.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .frame(height: 60)
        .background(Color(UIColor.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.gray.opacity(0.3)),
            alignment: .top
        )
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
