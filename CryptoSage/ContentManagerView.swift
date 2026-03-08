//
//  ContentManagerView.swift
//  CryptoSage
//
//  Created by DM on 3/16/25.
//
//  Manages the TabView and switches between tabs.
//  PERFORMANCE: Uses lazy tab loading - only active tab is rendered.
//  TradeView is kept alive once visited to preserve expensive WebView.
//

import SwiftUI

struct ContentManagerView: View {
    @EnvironmentObject var appState: AppState
    
    /// Track if TradeView has been visited - once visited, keep it alive for WebView persistence
    @State private var hasVisitedTrade: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // PERFORMANCE: Lazy tab loading - only render active tab
            // Exception: TradeView stays alive once visited (WebView persistence)
            ZStack {
                // Active tab content - only one rendered at a time (except TradeView persistence)
                activeTabContent
                
                // TradeView persistence layer - kept alive once visited to preserve WebView
                // Uses opacity 0 when not active to avoid expensive re-creation
                if hasVisitedTrade {
                    TradeView()
                        .opacity(appState.selectedTab == .trade ? 1 : 0)
                        .allowsHitTesting(appState.selectedTab == .trade)
                        .zIndex(appState.selectedTab == .trade ? 1 : 0)
                }
            }

            CustomTabBar(selectedTab: $appState.selectedTab)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAgentTrading)) { _ in
            // Switch to Portfolio tab where the agent dashboard section lives
            appState.selectedTab = .portfolio
        }
        .onChange(of: appState.selectedTab) { _, newTab in
            // Mark TradeView as visited for persistence
            if newTab == .trade {
                hasVisitedTrade = true
                // PERFORMANCE FIX: Trigger WebKit prewarming when user navigates to Trade
                // This is better than prewarming at app launch because:
                // 1. User is already on the Trade tab, so WebView init won't cause scroll jank
                // 2. WebView is actually needed now, so initialization is justified
                // 3. The initial load time is expected by the user
                Task { @MainActor in
                    WebKitPrewarmer.shared.warmUpIfNeeded()
                }
            }
        }
    }
    
    /// Returns only the currently active tab view (lazy loading)
    /// TradeView is handled separately for WebView persistence
    @ViewBuilder
    private var activeTabContent: some View {
        switch appState.selectedTab {
        case .home:
            HomeView(selectedTab: $appState.selectedTab)
                .transition(.identity) // No animation for instant switching
        case .market:
            MarketView()
                .transition(.identity)
        case .trade:
            // TradeView handled in persistence layer above
            // Show empty placeholder when TradeView hasn't been visited yet
            if !hasVisitedTrade {
                TradeView()
                    .onAppear { hasVisitedTrade = true }
            } else {
                // TradeView is in the persistence layer, show nothing here
                Color.clear.frame(width: 0, height: 0)
            }
        case .portfolio:
            PortfolioView()
                .transition(.identity)
        case .ai:
            AITabView()
                .transition(.identity)
        }
    }
}

struct ContentManagerView_Previews: PreviewProvider {
    static var previews: some View {
        ContentManagerView()
            .environmentObject(AppState())
            .environmentObject(MarketViewModel.shared)
    }
}
