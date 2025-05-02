import SwiftUI
import Charts

// Temporary extension to add a default accountName property to Holding.
// When your API provides actual account info, update this accordingly.
extension Holding {
    var accountName: String {
        return "Default"
    }
}

private let brandAccent = Color("BrandAccent")

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct PortfolioView: View {
    @EnvironmentObject var homeVM: HomeViewModel
    private var portfolioVM: PortfolioViewModel { homeVM.portfolioVM }
    @State private var displayedTotal: Double = 0
    
    // Tab selection
    @State private var selectedTab: Int = 0
    
    // Search
    @State private var showSearchBar = false
    @State private var searchTerm = ""
    
    // Chart mode state lifted up for parent-level management
    @State private var chartMode: ChartViewType = .line
    
    // Sheets
    @State private var showAddSheet = false
    @State private var showSettingsSheet = false
    @State private var showPaymentMethodsSheet = false
    
    // Tooltip / legend
    @State private var showLegend = false
    @State private var showTooltip = false
    
    // Filtered holdings to display: Filter by search term.
    private var displayedHoldings: [Holding] {
        var base = portfolioVM.holdings
        if showSearchBar, !searchTerm.isEmpty {
            base = base.filter {
                $0.coinName.lowercased().contains(searchTerm.lowercased()) ||
                $0.coinSymbol.lowercased().contains(searchTerm.lowercased())
            }
        }
        return base
    }
    
    var body: some View {
        ZStack {
            FuturisticBackground()
            
            VStack(spacing: 0) {
                // MARK: - Top Tab Bar
                HStack(spacing: 0) {
                    Button {
                        withAnimation { selectedTab = 0 }
                    } label: {
                        VStack(spacing: 2) {
                            Text("Portfolio")
                                .font(.headline)
                            Text("Track your assets & P/L")
                                .font(.caption)
                        }
                        .foregroundColor(selectedTab == 0 ? .white : .gray)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(selectedTab == 0 ? brandAccent.opacity(0.3) : Color.clear)
                        .cornerRadius(8)
                    }
                    .buttonStyle(ScaleButtonStyle())
                    
                    Button {
                        withAnimation { selectedTab = 1 }
                    } label: {
                        Text("Transactions")
                            .font(.headline)
                            .foregroundColor(selectedTab == 1 ? .white : .gray)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(selectedTab == 1 ? brandAccent.opacity(0.3) : Color.clear)
                            .cornerRadius(8)
                    }
                    .buttonStyle(ScaleButtonStyle())
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 8)
                
                // Content switcher based on selected tab
                if selectedTab == 0 {
                    overviewTab
                } else {
                    transactionsTab
                }
            }
        }
        .onAppear {
            // Sync displayedTotal to the VM's totalValue on appear
            displayedTotal = portfolioVM.totalValue
        }
        .onDisappear {
            // No cleanup needed; subscriptions are tied to the VM lifecycle
        }
        .onChange(of: portfolioVM.totalValue) { newValue in
            withAnimation(.easeOut(duration: 0.5)) {
                displayedTotal = newValue
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddTransactionView(viewModel: portfolioVM)
        }
        .sheet(isPresented: $showSettingsSheet) {
            SettingsView()
        }
        .sheet(isPresented: $showPaymentMethodsSheet) {
            PortfolioPaymentMethodsView()
        }
        .preferredColorScheme(AppTheme.currentColorScheme)
    }
}

// MARK: - PortfolioView Subviews
extension PortfolioView {
    
    private var overviewTab: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                headerCard
                PortfolioChartView(
                    portfolioVM: portfolioVM,
                    showMetrics: false,
                    showSelector: true,
                    chartMode: $chartMode
                )
                .padding(.horizontal, 16)
                holdingsSection
                connectExchangesSection
            }
            .padding(.bottom, 100)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var transactionsTab: some View {
        VStack {
            HStack {
                Text("Transactions")
                    .font(.headline)
                Spacer()
                Button {
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.title2)
                        .foregroundColor(.yellow)
                }
            }
            .padding(.horizontal)
            .padding(.top, 16)
            
            List {
                ForEach(portfolioVM.transactions) { tx in
                    TransactionRowView(transaction: tx)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if tx.isManual {
                                Button(role: .destructive) {
                                    portfolioVM.deleteManualTransaction(tx)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                Button {
                                    portfolioVM.editingTransaction = tx
                                    showAddSheet = true
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                }
            }
            .listStyle(PlainListStyle())
        }
    }
    
    // MARK: - Header Card Components

    private var headerCard: some View {
        ZStack {
            headerBackground
            headerContent
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var headerBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.gray.opacity(0.2),
                        Color.black.opacity(0.4)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
    }

    private var headerContent: some View {
        HStack {
            metricsVStack
            Spacer()
            chartSection
        }
        .padding(.vertical, 12)
    }

    private var metricsVStack: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(displayedTotal, format: .currency(code: "USD"))
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
            Text("Total Value")
                .foregroundColor(portfolioVM.totalValue >= 0 ? .green : .red)
                .font(.subheadline)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("24h Change")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    HStack(spacing: 4) {
                        Image(systemName: portfolioVM.dailyChangePercent >= 0 ? "arrow.up" : "arrow.down")
                        Text(portfolioVM.dailyChangePercentString)
                    }
                    .font(.subheadline)
                    .foregroundColor(portfolioVM.dailyChangePercent >= 0 ? .green : .red)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total P/L")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    HStack(spacing: 4) {
                        Text(portfolioVM.unrealizedPLString)
                    }
                    .font(.subheadline)
                    .foregroundColor(portfolioVM.unrealizedPL >= 0 ? .green : .red)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                }
                Spacer()
            }
            .padding(.top, 4)
        }
        .padding(.leading, 16)
    }


    // MARK: - Chart Subsections

    private var chartSection: some View {
        Group {
            if chartMode == .line {
                linePieSection
            } else {
                performanceSection
            }
        }
    }

    private var linePieSection: some View {
        ThemedPortfolioPieChartView(
            portfolioVM: portfolioVM,
            showLegend: $showLegend
        )
        .frame(width: 80, height: 80)
        .onTapGesture {
            withAnimation { showLegend.toggle() }
        }
        .padding(.trailing, 16)
        .overlay(
            Group {
                if showLegend {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(portfolioVM.allocationData, id: \.symbol) { slice in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(portfolioVM.color(for: slice.symbol))
                                    .frame(width: 10, height: 10)
                                Text(slice.symbol)
                                    .font(.caption2)
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(8)
                    .transition(.opacity)
                    .onTapGesture {
                        withAnimation { showLegend = false }
                    }
                }
            },
            alignment: .topTrailing
        )
    }

    private var performanceSection: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Top Performer")
                    .font(.caption2)
                    .foregroundColor(.gray)
                Text(portfolioVM.topPerformerString)
                    .font(.headline)
                    .foregroundColor(portfolioVM.topPerformerString.contains("+") ? .green : .red)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Worst Performer")
                    .font(.caption2)
                    .foregroundColor(.gray)
                Text(portfolioVM.worstPerformerString)
                    .font(.headline)
                    .foregroundColor(portfolioVM.worstPerformerString.contains("-") ? .red : .green)
            }
        }
        .padding(.trailing, 16)
    }
    
    
    private var holdingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Holdings")
                    .foregroundColor(.white)
                    .font(.headline)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showSearchBar.toggle()
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, 16)
            
            if showSearchBar {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("Search Holdings...", text: $searchTerm)
                        .foregroundColor(.white)
                }
                .padding()
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(brandAccent.opacity(0.5), lineWidth: 1)
                )
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: showSearchBar)
                .padding(.horizontal, 16)
            }
            
            LazyVStack(spacing: 8) {
                ForEach(displayedHoldings) { holding in
                    PortfolioCoinRow(viewModel: portfolioVM, holding: holding)
                        .padding(.horizontal, 16)
                }
                .onDelete { indexSet in
                    portfolioVM.removeHolding(at: indexSet)
                }
            }
            .padding(.top, 8)
        }
        .padding(.top, 8)
    }
    
    private var connectExchangesSection: some View {
        HStack(spacing: 8) {
            Button {
                linkExchanges()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "link.circle.fill")
                    Text("Connect Exchanges & Wallets")
                        .fontWeight(.medium)
                }
                .font(.subheadline)
                .foregroundColor(.white)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(brandAccent.opacity(0.3))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(ScaleButtonStyle())
            
            Button {
                showTooltip.toggle()
            } label: {
                Image(systemName: "questionmark.circle")
                    .foregroundColor(.white)
                    .font(.title3)
            }
            .popover(isPresented: $showTooltip) {
                Text("Link your accounts to trade seamlessly.\nThis is a quick info popover!")
                    .padding()
                    .foregroundColor(.white)
                    .background(Color.black)
                    .cornerRadius(8)
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
    
    private var transactionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeading("Recent Transactions", iconName: "clock.arrow.circlepath")
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
    
    private var communitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeading("Community & Social", iconName: "person.3.fill")
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
    
    private func sectionHeading(_ text: String, iconName: String? = nil) -> some View {
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
    
    // Updated stub function for linking exchanges and wallets.
    private func linkExchanges() {
        // Now toggles the sheet state to show the PortfolioPaymentMethodsView.
        showPaymentMethodsSheet = true
    }
}

// MARK: - Preview
struct PortfolioView_Previews: PreviewProvider {
    static var previews: some View {
        PortfolioView()
            .environmentObject(HomeViewModel())
            .preferredColorScheme(.dark)
    }
}
