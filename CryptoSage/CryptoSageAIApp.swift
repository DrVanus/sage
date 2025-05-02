import SwiftUI
import UIKit
import Combine

@main
struct CryptoSageAIApp: App {
    @StateObject private var appState: AppState
    @StateObject private var marketVM: MarketViewModel
    @StateObject private var portfolioVM: PortfolioViewModel
    @StateObject private var newsVM: CryptoNewsFeedViewModel
    @StateObject private var segmentVM: MarketSegmentViewModel
    @StateObject private var dataModeManager: DataModeManager
    @StateObject private var homeVM: HomeViewModel
    @StateObject private var chatVM: ChatViewModel

    init() {
        let appState = AppState()
        let marketVM = MarketViewModel.shared
        let dm = DataModeManager()
        let homeVM = HomeViewModel()
        let chatVM = ChatViewModel()
        _appState = StateObject(wrappedValue: appState)
        _marketVM = StateObject(wrappedValue: marketVM)
        _dataModeManager = StateObject(wrappedValue: dm)
        _homeVM = StateObject(wrappedValue: homeVM)
        _chatVM = StateObject(wrappedValue: chatVM)

        let manualService = ManualPortfolioDataService()
        let liveService   = LivePortfolioDataService()
        let priceService  = CoinGeckoPriceService()
        let repository    = PortfolioRepository(
            manualService: manualService,
            liveService:   liveService,
            priceService:  priceService
        )
        _portfolioVM = StateObject(
            wrappedValue: PortfolioViewModel(repository: repository)
        )

        _newsVM = StateObject(wrappedValue: CryptoNewsFeedViewModel())
        _segmentVM = StateObject(wrappedValue: MarketSegmentViewModel())
        // Global navigation bar appearance
        let navBarAppearance = UINavigationBarAppearance()
        navBarAppearance.configureWithOpaqueBackground()
        navBarAppearance.backgroundColor = UIColor.black
        navBarAppearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        UINavigationBar.appearance().standardAppearance = navBarAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navBarAppearance
        UINavigationBar.appearance().tintColor = .white

        // Initialize compliance manager to detect user jurisdiction
        ComplianceManager.shared.detectUserCountry { error in
            if let error = error {
                print("ComplianceManager error detecting user country: \(error)")
            }
        }
        // Kick off initial data load for Market view model only
        Task {
            await marketVM.loadAllData()
        }
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ZStack {
                    Group {
                        switch appState.selectedTab {
                        case .home:
                            HomeView(selectedTab: $appState.selectedTab)
                        case .market:
                            MarketView()
                        case .trade:
                            TradeView()
                        case .portfolio:
                            PortfolioView()
                        case .ai:
                            AITabView()
                        }
                    }

                    VStack {
                        Spacer()
                        CustomTabBar(selectedTab: $appState.selectedTab)
                    }
                }
            }
            .accentColor(.white)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .environmentObject(appState)
            .environmentObject(marketVM)
            .environmentObject(portfolioVM)
            .environmentObject(newsVM)
            .environmentObject(segmentVM)
            .environmentObject(dataModeManager)
            .environmentObject(homeVM)
            .environmentObject(chatVM)
            .preferredColorScheme(appState.isDarkMode ? .dark : .light)
        }
    }
}

class AppState: ObservableObject {
    @Published var selectedTab: CustomTab = .home
    @Published var isDarkMode: Bool = true
}
