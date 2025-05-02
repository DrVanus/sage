//
//  HomeView.swift
//  CSAI1
//
//  Created by ChatGPT on 3/27/25
//

import SwiftUI
// Add this import if needed:
// import BookmarksViewModule // if BookmarksView is in a separate module

// Example AI prompt suggestions
private let promptExamples = [
    "How can I improve my portfolio diversification?",
    "What trades performed best last week?",
    "Should I rebalance my assets now?"
]
import Combine
// import HomeViewModel   // if HomeViewModel is in a separate file; omit if in same module
import SafariServices
// Make sure ThemedPortfolioPieChartView is imported or available in this file.

/// Shared placeholder container for images
struct PlaceholderImage<Content: View>: View {
    let content: () -> Content
    var body: some View {
        ZStack {
            Rectangle().fill(Color.gray.opacity(0.2))
            content()
        }
        .frame(width: 120, height: 70)
        .cornerRadius(8)
        .clipped()
    }
}


/// A reusable heading with optional icon.
struct SectionHeading: View {
    let text: String
    let iconName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if let icon = iconName {
                    Image(systemName: icon)
                        .foregroundColor(.yellow)
                }
                Text(text)
                    .font(.title3).bold()
                    .foregroundColor(.white)
            }
            Divider()
                .background(Color.white.opacity(0.15))
        }
    }
}


// MARK: - Crypto News ViewModel
// (Old CoinStats news VM removed; use CryptoNewsFeedViewModel instead)

// MARK: - News Models
// NewsArticle and NewsPreviewRow are likely replaced by RSS model/row elsewhere.

// MARK: - Gold Button Style
struct CSGoldButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption)
            .foregroundColor(.black)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 1.0, green: 0.84, blue: 0.0),
                        Color.orange
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(10)
            .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 2)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(), value: configuration.isPressed)
    }
}

 

// MARK: - (Optional) HomeLineChart
struct HomeLineChart: View {
    let data: [Double]
    var body: some View {
        GeometryReader { geo in
            if data.count > 1,
               let minVal = data.min(),
               let maxVal = data.max(),
               maxVal > minVal {

                let range = maxVal - minVal
                Path { path in
                    for (index, value) in data.enumerated() {
                        let xPos = geo.size.width * CGFloat(index) / CGFloat(data.count - 1)
                        let yPos = geo.size.height * (1 - CGFloat((value - minVal) / range))
                        if index == 0 {
                            path.move(to: CGPoint(x: xPos, y: yPos))
                        } else {
                            path.addLine(to: CGPoint(x: xPos, y: yPos))
                        }
                    }
                }
                .stroke(Color.green, lineWidth: 2)

                Path { path in
                    for (index, value) in data.enumerated() {
                        let xPos = geo.size.width * CGFloat(index) / CGFloat(data.count - 1)
                        let yPos = geo.size.height * (1 - CGFloat((value - minVal) / range))
                        if index == 0 {
                            path.move(to: CGPoint(x: xPos, y: geo.size.height))
                            path.addLine(to: CGPoint(x: xPos, y: yPos))
                        } else {
                            path.addLine(to: CGPoint(x: xPos, y: yPos))
                        }
                    }
                    path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    path.closeSubpath()
                }
                .fill(Color.green.opacity(0.2))

            } else {
                Text("No Chart Data")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - CoinCardView
struct CoinCardView: View {
    let coin: MarketCoin

    var body: some View {
        VStack(spacing: 6) {
            coinIconView(for: coin, size: 32)

            Text(coin.symbol.uppercased())
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(1)

            if let priceValue = coin.priceUsd {
                Text(formatPrice(priceValue))
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .lineLimit(1)
            } else {
                Text("–")
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .lineLimit(1)
            }

            Text("\(coin.changePercent24Hr ?? 0.0, specifier: "%.2f")%")
                .font(.caption)
                .foregroundColor((coin.changePercent24Hr ?? 0.0) >= 0 ? .green : .red)
        }
        .frame(width: 90, height: 120)
        .padding(6)
        .background(Color.white.opacity(0.05))
        .cornerRadius(10)
        .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
    }

@ViewBuilder
private func coinIconView(for coin: MarketCoin, size: CGFloat) -> some View {
    if let url = coin.iconUrl {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else if phase.error != nil {
                Circle().fill(Color.gray.opacity(0.3))
                    .frame(width: size, height: size)
            } else {
                ProgressView().frame(width: size, height: size)
            }
        }
    } else {
        Circle().fill(Color.gray.opacity(0.3))
            .frame(width: size, height: size)
    }
}

    private func formatPrice(_ value: Double) -> String {
        guard value > 0 else { return "$0.00" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        if value < 1.0 {
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 8
        } else {
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
        }
        return "$" + (formatter.string(from: NSNumber(value: value)) ?? "0.00")
    }
}

// MARK: - HomeView
struct HomeView: View {
    @StateObject var vm = HomeViewModel()
    @Binding var selectedTab: CustomTab
    @EnvironmentObject var chatVM: ChatViewModel

    @StateObject private var notificationsManager = NotificationsManager.shared
    @State private var showSettings = false
    @State private var displayedTotal: Double = 0
    @State private var showNotifications = false
    @State private var selected: HeatMapTile?
    @EnvironmentObject var marketVM: MarketViewModel
    @EnvironmentObject var newsVM: CryptoNewsFeedViewModel
    @State private var showHomePieLegend = false

    /// Track the last visible article for scroll restoration
    @State private var lastSeenArticleID: String?

    var body: some View {
        ZStack {
            FuturisticBackground()
                .ignoresSafeArea()
            Group {
                ScrollView(.vertical, showsIndicators: false) {
                    homeContentStack
                }
                .task {
                    await newsVM.loadLatestNews()
                }
                .background(Color.black)
                .scrollContentBackground(.hidden)
            }
            .background(Color.black)
            .accentColor(.white)
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing:
                HStack(spacing: 16) {
                    Button(action: { showNotifications = true }) {
                        Image(systemName: "bell")
                            .foregroundColor(.white)
                    }
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                            .foregroundColor(.white)
                    }
                }
            )
            .sheet(isPresented: $showNotifications) {
                NotificationsView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .task {
                await marketVM.loadAllData()
            }
            .onChange(of: vm.portfolioVM.totalValue) { newValue in
                withAnimation(.easeOut(duration: 0.8)) {
                    displayedTotal = newValue
                }
            }
            .onAppear {
                displayedTotal = vm.portfolioVM.totalValue
            }
        }
    }

    @ViewBuilder
    private var contentScrollView: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                homeContentStack
            }
        }
        .background(Color.black)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Portfolio Summary Header

    private var portfolioSummaryHeader: some View {
        headerContent
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.05))
                    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
            )
            .padding(.horizontal, 16)
    }

    @ViewBuilder private var headerContent: some View {
        HStack(alignment: .center) {
            metricsVStack
            Spacer()
            ThemedPortfolioPieChartView(
                portfolioVM: vm.portfolioVM,
                showLegend: $showHomePieLegend
            )
            .frame(width: 80, height: 80)
            .padding(.trailing, 16)
            .onTapGesture {
                withAnimation {
                    showHomePieLegend.toggle()
                }
            }
        }
        if showHomePieLegend {
            pieLegendVStack
                .padding(.top, 8)
                .padding(.horizontal, 32)
        }
    }

    private var metricsVStack: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Portfolio")
                .font(.title3).bold()
                .foregroundColor(.white)
            Text(displayedTotal, format: .currency(code: "USD"))
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("24h Change")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    HStack(spacing: 4) {
                        Image(systemName: vm.portfolioVM.dailyChangePercent >= 0 ? "arrow.up" : "arrow.down")
                        Text(vm.portfolioVM.dailyChangePercentString)
                    }
                    .font(.subheadline)
                    .foregroundColor(vm.portfolioVM.dailyChangePercent >= 0 ? .green : .red)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total P/L")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    HStack(spacing: 4) {
                        Text(vm.portfolioVM.unrealizedPLString)
                    }
                    .font(.subheadline)
                    .foregroundColor(vm.portfolioVM.unrealizedPL >= 0 ? .green : .red)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                }
                Spacer()
            }
            .padding(.top, 4)
        }
    }


    // Color helper to work around EnvironmentObject lookup
    private func color(for symbol: String) -> Color {
        vm.portfolioVM.color(for: symbol)
    }

    private var pieLegendVStack: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(vm.portfolioVM.allocationData, id: \.symbol) { slice in
                HStack(spacing: 8) {
                    Circle()
                        .fill(slice.color)
                        .frame(width: 10, height: 10)
                    Text("\(slice.symbol): \(slice.percent, specifier: "%.0f")%")
                        .font(.caption)
                        .foregroundColor(.white)
                }
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.8))
        .cornerRadius(8)
    }



    private var homeContentStack: some View {
        VStack(alignment: .leading, spacing: 16) {
            portfolioSummaryHeader

            // Inline AIInsightBlock
            AIInsightBlock(portfolioViewModel: vm.portfolioVM)
                .padding(.horizontal, 16)

            // AI Insights navigation link
            NavigationLink(destination: AllAIInsightsView()) {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.yellow)
                    Text("More AI Insights")
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 10)
                                .fill(Color.white.opacity(0.05)))
            }
            .padding(.horizontal, 16)

            // AI Prompt Suggestions
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(promptExamples, id: \.self) { prompt in
                        Button(action: {
                            chatVM.inputText = prompt
                            selectedTab = .ai
                        }) {
                            Text(prompt)
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            // Deep-Dive Sections
            WatchlistSection()
            marketStatsSection
            sentimentSection
            heatmapSection
            aiAndInviteSection
            trendingSection
            topMoversSection
            arbitrageSection
            eventsSection
            exploreSection
            newsPreviewSection
            seeAllNewsLinkSection
            transactionsSection
            communitySection
            footer
        }
    }

    private var marketStatsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(text: "Market Stats", iconName: "chart.bar.xaxis")
            MarketStatsView()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
        )
    }

    private var sentimentSection: some View {
        MarketSentimentView()
            .frame(maxWidth: .infinity)
    }

    private var heatmapSection: some View {
        MarketHeatMapSection()
            .padding(.horizontal, 16)
    }

    private var newsPreviewSection: some View {
        NewsPreviewSection(viewModel: newsVM, lastSeenArticleID: $lastSeenArticleID)
    }
// MARK: - News Preview Section Subview
private struct NewsPreviewSection: View {
    @ObservedObject var viewModel: CryptoNewsFeedViewModel
    @Binding var lastSeenArticleID: String?
    /// Prevent auto-scrolling on initial load
    @State private var hasRestoredScroll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(text: "Latest Crypto News", iconName: "newspaper")
                .padding(.horizontal, 16)
            ScrollViewReader { proxy in
                content(proxy: proxy)
            }
        }
        .onDisappear {
            // Reset so we skip scroll when returning
            hasRestoredScroll = false
        }
    }

    @ViewBuilder
    private func content(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 8) {
            if viewModel.isLoading {
                loadingView
            } else if viewModel.articles.isEmpty {
                emptyView
            } else {
                articlesView(proxy: proxy)
            }
        }
        .onChange(of: lastSeenArticleID) { newID in
            // Skip auto-scroll on initial appearance
            guard hasRestoredScroll, let id = newID else {
                hasRestoredScroll = true
                return
            }
            withAnimation {
                proxy.scrollTo(id, anchor: .top)
            }
        }
    }

    private var loadingView: some View {
        ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: .white))
            .frame(maxWidth: .infinity)
    }

    private var emptyView: some View {
        Text("No news available.")
            .foregroundColor(.gray)
            .frame(maxWidth: .infinity)
    }

    private func articlesView(proxy: ScrollViewProxy) -> some View {
        ForEach(viewModel.articles.prefix(3)) { article in
            HStack(alignment: .center, spacing: 12) {
                PlaceholderImage {
                    AsyncImage(url: article.urlToImage) { phase in
                        switch phase {
                        case .empty:
                            loadingView
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            Image(systemName: "photo")
                                .resizable()
                                .scaledToFit()
                                .foregroundColor(.gray)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(article.title)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Text(article.sourceName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(article.relativeTime)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .id(article.id)
            .padding(.vertical, 8)
            .onTapGesture { openSafari(article.url) }
            .onAppear { lastSeenArticleID = article.id }
        }
    }
}

    private var seeAllNewsLinkSection: some View {
        HStack {
            NavigationLink(destination: AllCryptoNewsView()
                            .environmentObject(newsVM)
                            .navigationTitle("Crypto News")
                            .navigationBarTitleDisplayMode(.inline)
            ) {
                Text("See All News")
                    .font(.body)
                    .foregroundColor(.yellow)
            }
        }
    }

}

// MARK: - HomeView Subviews (Extension)
extension HomeView {



    // AI & Invite Section
    private var aiAndInviteSection: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "exclamationmark.shield")
                        .foregroundColor(.green)
                    Text("AI Risk Scan")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                Text("Quickly analyze your portfolio risk.")
                    .font(.caption)
                    .foregroundColor(.gray)
                Button("Scan Now") {}
                    .buttonStyle(CSGoldButtonStyle())
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.05))
                    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "gift")
                        .foregroundColor(.yellow)
                    Text("Invite & Earn BTC")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                Text("Refer friends, get rewards.")
                    .font(.caption)
                    .foregroundColor(.gray)
                Button("Invite Now") {}
                    .buttonStyle(CSGoldButtonStyle())
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.05))
                    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
            )
        }
    }

    // Trending Section
    private var trendingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(text: "Trending", iconName: "flame")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(marketVM.trendingCoins) { coin in
                        CoinCardView(coin: coin)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
        )
    }

    // Top Movers Section
    private var topMoversSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(text: "Top Gainers", iconName: "arrow.up.right")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(marketVM.topGainers) { coin in
                        CoinCardView(coin: coin)
                    }
                }
                .padding(.vertical, 6)
            }

            SectionHeading(text: "Top Losers", iconName: "arrow.down.right")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 16) {
                    ForEach(marketVM.topLosers) { coin in
                        CoinCardView(coin: coin)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
        )
    }

    // Arbitrage Section
    private var arbitrageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(text: "Arbitrage Opportunities", iconName: "arrow.left.and.right.circle")
            Text("Find price differences across exchanges for potential profit.")
                .font(.caption)
                .foregroundColor(.gray)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("BTC/USDT")
                        .foregroundColor(.white)
                    Text("Ex A: $65,000\nEx B: $66,200\nPotential: $1,200")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("ETH/USDT")
                        .foregroundColor(.white)
                    Text("Ex A: $1,800\nEx B: $1,805\nProfit: $5")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
        )
    }

    // Events Section
    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(text: "Events Calendar", iconName: "calendar")
            Text("Stay updated on upcoming crypto events.")
                .font(.caption)
                .foregroundColor(.gray)
            VStack(alignment: .leading, spacing: 4) {
                Text("• ETH2 Hard Fork")
                    .foregroundColor(.white)
                Text("May 30 • Upgrade to reduce fees")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("• DOGE Conference")
                    .foregroundColor(.white)
                Text("June 10 • Global doge event")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("• SOL Hackathon")
                    .foregroundColor(.white)
                Text("June 15 • Dev grants for new apps")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
        )
    }

    // Explore Section
    private var exploreSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(text: "Explore", iconName: "magnifyingglass")
            Text("Discover advanced AI and market features.")
                .font(.caption)
                .foregroundColor(.gray)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Market Scan")
                        .font(.subheadline)
                        .foregroundColor(.white)
                    Text("Scan market signals, patterns.")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("DeFi Analytics")
                        .font(.subheadline)
                        .foregroundColor(.white)
                    Text("Monitor yields, track TVL.")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("NFT Explorer")
                        .font(.subheadline)
                        .foregroundColor(.white)
                    Text("Browse trending collections.")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
        )
    }


    // Transactions Section
    private var transactionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(text: "Recent Transactions", iconName: "clock.arrow.circlepath")
            transactionRow(action: "Buy BTC", change: "+0.012 BTC", value: "$350", time: "3h ago")
            transactionRow(action: "Sell ETH", change: "-0.05 ETH", value: "$90", time: "1d ago")
            transactionRow(action: "Stake SOL", change: "+10 SOL", value: "", time: "2d ago")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
        )
    }

    private func transactionRow(action: String, change: String, value: String, time: String) -> some View {
        HStack {
            Text(action)
                .foregroundColor(.white)
            Spacer()
            VStack(alignment: .trailing) {
                Text(change)
                    .foregroundColor(change.hasPrefix("-") ? .red : .green)
                if !value.isEmpty {
                    Text(value)
                        .foregroundColor(.gray)
                }
            }
            Text(time)
                .foregroundColor(.gray)
                .font(.caption)
                .frame(width: 50, alignment: .trailing)
        }
    }

    // Community Section
    private var communitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeading(text: "Community & Social", iconName: "person.3.fill")
            Text("Join our Discord, follow us on Twitter, or vote on community proposals.")
                .font(.caption)
                .foregroundColor(.gray)
            HStack(spacing: 16) {
                VStack {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                    Text("Discord")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                VStack {
                    Image(systemName: "bird")
                        .font(.title3)
                        .foregroundColor(.white)
                    Text("Twitter")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                VStack {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                    Text("Governance")
                        .font(.caption)
                        .foregroundColor(.white)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.05))
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
        )
    }

    // Footer
    private var footer: some View {
        VStack(spacing: 4) {
            Text("CryptoSage AI v1.0.0 (Beta)")
                .font(.footnote)
                .foregroundColor(.white.opacity(0.6))
            Text("All information is provided as-is and is not guaranteed to be accurate. Final decisions are your own responsibility.")
                .font(.caption2)
                .foregroundColor(.gray.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 8)
    }


    // Stat Cell Helper
    private func statCell(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.gray)
                Text(value)
                    .font(.subheadline)
                    .foregroundColor(.white)
            }
        }
    }


    // Format Price Helper
    private func formatPrice(_ value: Double) -> String {
        guard value > 0 else { return "$0.00" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        if value < 1.0 {
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 8
        } else {
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
        }
        return "$" + (formatter.string(from: NSNumber(value: value)) ?? "0.00")
    }
}








    /// Present a SFSafariViewController over the root window.
    private func openSafari(_ url: URL) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else {
            return
        }
        let safari = SFSafariViewController(url: url)
        safari.modalPresentationStyle = .fullScreen
        root.present(safari, animated: true)
    }

// MARK: - Preview
struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        HomeView(selectedTab: .constant(.home))
            .environmentObject(ChatViewModel())
            // Add other environment objects as needed for previews:
            // .environmentObject(MarketViewModel.sample)
            // .environmentObject(CryptoNewsFeedViewModel.sample)
    }
}
