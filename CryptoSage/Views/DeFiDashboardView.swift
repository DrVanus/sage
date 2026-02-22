//
//  DeFiDashboardView.swift
//  CryptoSage
//
//  Unified dashboard for all DeFi positions, NFTs, and wallet tracking.
//

import SwiftUI

// MARK: - DeFi Dashboard View

struct DeFiDashboardView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var defiVM = DeFiPositionsViewModel.shared
    @StateObject private var nftVM = NFTCollectionViewModel.shared
    @StateObject private var multiChainVM = MultiChainPortfolioViewModel.shared
    @ObservedObject private var demoModeManager = DemoModeManager.shared
    
    @State private var selectedTab: DeFiTab = .overview
    @State private var appeared = false
    
    private let cardCornerRadius: CGFloat = 16
    
    /// Theme-consistent accent color (gold in dark mode, blue in light mode)
    private var themedAccent: Color {
        colorScheme == .dark ? Color(red: 1.0, green: 0.84, blue: 0.0) : .blue
    }
    
    /// Gold gradient for back button (matches other views)
    private var chipGoldGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // MARK: - Demo Mode Data
    
    private var isDemoMode: Bool {
        demoModeManager.isDemoMode
    }
    
    private var displayedWallets: [ConnectedChainWallet] {
        isDemoMode ? DemoDataProvider.demoWallets : multiChainVM.connectedWallets
    }
    
    private var displayedNFTs: [NFT] {
        isDemoMode ? DemoDataProvider.demoNFTs : nftVM.nfts
    }
    
    private var displayedPositions: [DeFiPosition] {
        isDemoMode ? DemoDataProvider.demoPositions : defiVM.positions
    }
    
    private var displayedWalletValue: Double {
        isDemoMode ? DemoDataProvider.demoTotalWalletValue : multiChainVM.totalValue
    }
    
    private var displayedNFTValue: Double {
        isDemoMode ? DemoDataProvider.demoTotalNFTValue : nftVM.totalEstimatedValue
    }
    
    private var displayedDeFiValue: Double {
        isDemoMode ? DemoDataProvider.demoTotalDeFiValue : defiVM.totalValue
    }
    
    enum DeFiTab: String, CaseIterable {
        case overview = "Overview"
        case wallets = "Wallets"
        case nfts = "NFTs"
        case positions = "DeFi"
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Premium background
                FuturisticBackground()
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Custom Header
                    customHeader
                    
                    // Demo Mode Banner
                    if isDemoMode {
                        demoModeBanner
                    }
                    
                    // Tab Selector
                    tabSelector
                    
                    // Content
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            switch selectedTab {
                            case .overview:
                                overviewContent
                            case .wallets:
                                walletsContent
                            case .nfts:
                                nftsContent
                            case .positions:
                                positionsContent
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom)
                    }
                    .refreshable {
                        await refreshAllAsync()
                    }
                }
            }
            .navigationBarHidden(true)
            .enableInteractivePopGesture()
            .edgeSwipeToDismiss(onDismiss: { dismiss() })
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) {
                    appeared = true
                }
            }
        }
    }
    
    // MARK: - Custom Header
    
    private var customHeader: some View {
        HStack(spacing: 0) {
            // Back button
            CSNavButton(
                icon: "chevron.left",
                action: { dismiss() }
            )
            
            Spacer()
            
            // Title
            Text("DeFi Portfolio")
                .font(.headline)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Spacer()
            
            // Add Wallet button
            NavigationLink {
                MultiChainWalletView()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(chipGoldGradient)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Add Wallet")
            
            // API Settings button (developer mode only)
            if SubscriptionManager.shared.isDeveloperMode {
                NavigationLink {
                    APIConfigurationView()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(chipGoldGradient)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("API Settings")
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(DS.Adaptive.background.opacity(0.95))
    }
    
    // MARK: - Tab Selector
    
    private var tabSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DeFiTab.allCases, id: \.self) { tab in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = tab
                        }
                    } label: {
                        Text(tab.rawValue)
                            .font(.subheadline)
                            .fontWeight(selectedTab == tab ? .semibold : .regular)
                            .foregroundColor(selectedTab == tab ? (colorScheme == .dark ? .black : .white) : DS.Adaptive.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Group {
                                    if selectedTab == tab {
                                        // Gold/silver gradient for selected
                                        LinearGradient(
                                            colors: colorScheme == .dark
                                                ? [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange]
                                                : [BrandColors.silverLight, BrandColors.silverBase],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    } else {
                                        // Glass background for unselected
                                        DS.Adaptive.cardBackground
                                    }
                                }
                            )
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(selectedTab == tab ? Color.clear : DS.Adaptive.stroke, lineWidth: 1)
                            )
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Overview Content
    
    private var overviewContent: some View {
        VStack(spacing: 16) {
            // Total Value Card
            totalValueCard
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 20)
                .animation(.easeOut(duration: 0.4).delay(0.1), value: appeared)
            
            // Quick Stats
            HStack(spacing: 12) {
                statCard(title: "Wallets", value: "\(displayedWallets.count)", icon: "wallet.pass.fill", color: .blue)
                statCard(title: "NFTs", value: "\(displayedNFTs.count)", icon: "photo.stack", color: .purple)
                statCard(title: "DeFi", value: "\(displayedPositions.count)", icon: "chart.pie", color: .green)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
            .animation(.easeOut(duration: 0.4).delay(0.2), value: appeared)
            
            // Recent Activity
            if !displayedWallets.isEmpty {
                recentWalletsSection
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                    .animation(.easeOut(duration: 0.4).delay(0.3), value: appeared)
            }
            
            // Featured NFTs
            if !displayedNFTs.isEmpty {
                featuredNFTsSection
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                    .animation(.easeOut(duration: 0.4).delay(0.4), value: appeared)
            }
            
            // Active DeFi Positions
            if !displayedPositions.isEmpty {
                activeDeFiSection
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                    .animation(.easeOut(duration: 0.4).delay(0.5), value: appeared)
            }
            
            // Empty state (only show when not in demo mode and everything is empty)
            if !isDemoMode && displayedWallets.isEmpty && displayedNFTs.isEmpty && displayedPositions.isEmpty {
                emptyStateView
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 20)
                    .animation(.easeOut(duration: 0.4).delay(0.3), value: appeared)
            }
        }
    }
    
    // MARK: - Wallets Content
    
    private var walletsContent: some View {
        VStack(spacing: 16) {
            if displayedWallets.isEmpty {
                // Premium empty state
                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.blue.opacity(0.2), .blue.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "wallet.pass")
                            .font(.system(size: 36))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .blue.opacity(0.7)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    
                    VStack(spacing: 8) {
                        Text("No Wallets Connected")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        Text("Connect your DeFi wallets to track balances across multiple chains.")
                            .font(.subheadline)
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    NavigationLink {
                        MultiChainWalletView()
                    } label: {
                        Label("Connect Wallet", systemImage: "plus")
                            .font(.headline)
                            .foregroundColor(colorScheme == .dark ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                LinearGradient(
                                    colors: colorScheme == .dark
                                        ? [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange]
                                        : [.blue, .blue.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 300)
                .background(premiumCardBackground)
            } else {
                ForEach(displayedWallets, id: \.id) { wallet in
                    walletCard(wallet)
                }
            }
        }
    }
    
    // MARK: - NFTs Content
    
    private var nftsContent: some View {
        VStack(spacing: 16) {
            if displayedNFTs.isEmpty {
                // Premium empty state
                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.purple.opacity(0.2), .purple.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "photo.stack")
                            .font(.system(size: 36))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.purple, .purple.opacity(0.7)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    
                    VStack(spacing: 8) {
                        Text("No NFTs Found")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        Text("Connect a wallet to view your NFT collection.")
                            .font(.subheadline)
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 300)
                .background(premiumCardBackground)
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    ForEach(displayedNFTs) { nft in
                        nftCard(nft)
                    }
                }
            }
        }
    }
    
    // MARK: - DeFi Positions Content
    
    private var positionsContent: some View {
        VStack(spacing: 16) {
            if displayedPositions.isEmpty {
                // Premium empty state
                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.green.opacity(0.2), .green.opacity(0.05)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: "chart.pie")
                            .font(.system(size: 36))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.green, .green.opacity(0.7)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    
                    VStack(spacing: 8) {
                        Text("No DeFi Positions")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        Text("Connect a wallet to track your DeFi positions across protocols.")
                            .font(.subheadline)
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(32)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 300)
                .background(premiumCardBackground)
            } else {
                ForEach(displayedPositions) { position in
                    defiPositionCard(position)
                }
            }
        }
    }
    
    // MARK: - Subviews
    
    private var totalValueCard: some View {
        VStack(spacing: 10) {
            Text("Total DeFi Value")
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
            
            Text(formatCurrency(totalValue))
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            HStack(spacing: 20) {
                valueBreakdown(label: "Tokens", value: displayedWalletValue)
                valueBreakdown(label: "NFTs", value: displayedNFTValue)
                valueBreakdown(label: "DeFi", value: displayedDeFiValue)
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                // Base card
                RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
                
                // Premium teal/blue gradient overlay
                LinearGradient(
                    colors: [
                        Color(red: 0.1, green: 0.4, blue: 0.5).opacity(colorScheme == .dark ? 0.3 : 0.15),
                        Color(red: 0.05, green: 0.25, blue: 0.35).opacity(colorScheme == .dark ? 0.2 : 0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
                
                // Top highlight
                LinearGradient(
                    colors: [Color.white.opacity(colorScheme == .dark ? 0.08 : 0.4), Color.clear],
                    startPoint: .top,
                    endPoint: .center
                )
                .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color(red: 0.2, green: 0.5, blue: 0.6).opacity(0.4),
                            DS.Adaptive.stroke,
                            DS.Adaptive.stroke,
                            Color(red: 0.2, green: 0.5, blue: 0.6).opacity(0.2)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
    
    private var totalValue: Double {
        displayedWalletValue + displayedNFTValue + displayedDeFiValue
    }
    
    private func valueBreakdown(label: String, value: Double) -> some View {
        VStack(spacing: 4) {
            Text(formatCurrency(value))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(DS.Adaptive.textPrimary)
            Text(label)
                .font(.caption)
                .foregroundColor(DS.Adaptive.textTertiary)
        }
    }
    
    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(color.opacity(colorScheme == .dark ? 0.2 : 0.12))
                    .frame(width: 44, height: 44)
                
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [color, color.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Text(title)
                .font(.caption)
                .foregroundColor(DS.Adaptive.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(premiumCardBackground)
    }
    
    private var recentWalletsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Wallets")
                    .font(.headline)
                    .foregroundColor(DS.Adaptive.textPrimary)
                Spacer()
                NavigationLink {
                    MultiChainWalletView()
                } label: {
                    Text("See All")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(themedAccent)
                }
            }
            
            ForEach(Array(displayedWallets.prefix(3).enumerated()), id: \.element.id) { index, wallet in
                walletRow(wallet)
                
                if index < min(2, displayedWallets.count - 1) {
                    Rectangle()
                        .fill(DS.Adaptive.divider)
                        .frame(height: 1)
                }
            }
        }
        .padding(16)
        .background(premiumCardBackground)
    }
    
    private var featuredNFTsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("NFTs")
                    .font(.headline)
                    .foregroundColor(DS.Adaptive.textPrimary)
                Spacer()
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    selectedTab = .nfts
                } label: {
                    Text("See All")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(themedAccent)
                }
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(displayedNFTs.prefix(5)) { nft in
                        nftThumbnail(nft)
                    }
                }
            }
        }
        .padding(16)
        .background(premiumCardBackground)
    }
    
    private var activeDeFiSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("DeFi Positions")
                    .font(.headline)
                    .foregroundColor(DS.Adaptive.textPrimary)
                Spacer()
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    selectedTab = .positions
                } label: {
                    Text("See All")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(themedAccent)
                }
            }
            
            ForEach(Array(displayedPositions.prefix(3).enumerated()), id: \.element.id) { index, position in
                defiPositionRow(position)
                
                if index < min(2, displayedPositions.count - 1) {
                    Rectangle()
                        .fill(DS.Adaptive.divider)
                        .frame(height: 1)
                }
            }
        }
        .padding(16)
        .background(premiumCardBackground)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            // Premium sparkle icon with gradient
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.25), Color.orange.opacity(0.1)]
                                : [.blue.opacity(0.15), .blue.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)
                
                Image(systemName: "sparkles")
                    .font(.system(size: 44))
                    .foregroundStyle(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange]
                                : [.blue, .blue.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            
            VStack(spacing: 10) {
                Text("Start Your DeFi Journey")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text("Connect your wallets to track tokens, NFTs, and DeFi positions across multiple blockchains.")
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            NavigationLink {
                MultiChainWalletView()
            } label: {
                Label("Connect First Wallet", systemImage: "wallet.pass.fill")
                    .font(.headline)
                    .foregroundColor(colorScheme == .dark ? .black : .white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange]
                                : [.blue, .blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(36)
        .frame(maxWidth: .infinity)
        .background(premiumCardBackground)
    }
    
    // MARK: - Demo Mode Banner
    
    private var demoModeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.caption2)
                .foregroundColor(colorScheme == .dark ? Color(red: 1.0, green: 0.84, blue: 0.0) : .blue)
            
            Text("Demo Mode – Sample data shown")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(DS.Adaptive.textSecondary)
            
            Spacer()
            
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                demoModeManager.disableDemoMode()
            } label: {
                Text("Disable")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(colorScheme == .dark ? .black : .white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange]
                                : [.blue, .blue.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(red: 1.0, green: 0.84, blue: 0.0).opacity(0.1), Color.orange.opacity(0.05)]
                    : [.blue.opacity(0.08), .blue.opacity(0.03)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }
    
    // MARK: - Premium Card Background
    
    private var premiumCardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
            
            // Top highlight
            LinearGradient(
                colors: [Color.white.opacity(colorScheme == .dark ? 0.06 : 0.5), Color.clear],
                startPoint: .top,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        }
        .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
    }
    
    // MARK: - Card Views
    
    private func walletCard(_ wallet: ConnectedChainWallet) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                ChainIcon(chainId: wallet.chainId)
                    .frame(width: 32, height: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(wallet.name ?? shortenAddress(wallet.address))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(DS.Adaptive.textPrimary)
                    Text(Chain(rawValue: wallet.chainId)?.displayName ?? "Unknown")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                Spacer()
                
                Text(formatCurrency(wallet.totalValueUSD ?? 0))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Adaptive.textPrimary)
            }
            
            if !wallet.tokenBalances.isEmpty {
                Rectangle()
                    .fill(DS.Adaptive.divider)
                    .frame(height: 1)
                
                ForEach(Array(wallet.tokenBalances.prefix(3))) { token in
                    tokenRow(token)
                }
                
                if wallet.tokenBalances.count > 3 {
                    Text("+\(wallet.tokenBalances.count - 3) more tokens")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
        }
        .padding(14)
        .background(premiumCardBackground)
    }
    
    private func walletRow(_ wallet: ConnectedChainWallet) -> some View {
        HStack {
            ChainIcon(chainId: wallet.chainId)
                .frame(width: 28, height: 28)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(wallet.name ?? shortenAddress(wallet.address))
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text("\(wallet.tokenBalances.count) tokens")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textSecondary)
            }
            
            Spacer()
            
            Text(formatCurrency(wallet.totalValueUSD ?? 0))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(DS.Adaptive.textPrimary)
        }
    }
    
    private func tokenRow(_ token: TokenBalance) -> some View {
        HStack {
            Text(token.symbol)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.4f", token.balance))
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textPrimary)
                if let value = token.valueUSD {
                    Text(formatCurrency(value))
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
            }
        }
    }
    
    private func nftCard(_ nft: NFT) -> some View {
        let imageURL = nft.imageURL.flatMap { URL(string: $0) }
        
        return VStack(alignment: .leading, spacing: 8) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(1, contentMode: .fill)
                case .failure:
                    nftPlaceholder(for: nft)
                case .empty:
                    if imageURL != nil {
                        // Loading state - show shimmer
                        ZStack {
                            LinearGradient(
                                colors: [
                                    DS.Adaptive.cardBackgroundElevated,
                                    DS.Adaptive.cardBackgroundElevated.opacity(0.7),
                                    DS.Adaptive.cardBackgroundElevated
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            ProgressView()
                                .tint(colorScheme == .dark ? Color(red: 1.0, green: 0.84, blue: 0.0) : .blue)
                        }
                    } else {
                        nftPlaceholder(for: nft)
                    }
                @unknown default:
                    nftPlaceholder(for: nft)
                }
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 1)
            )
            
            Text(nft.displayName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(DS.Adaptive.textPrimary)
                .lineLimit(1)
            
            if let collection = nft.collection?.name {
                Text(collection)
                    .font(.caption2)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .lineLimit(1)
            }
            
            if let price = nft.estimatedValueUSD {
                Text(formatCurrency(price))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
            }
        }
        .padding(10)
        .background(premiumCardBackground)
    }
    
    private func nftPlaceholder(for nft: NFT) -> some View {
        ZStack {
            // Gradient background based on collection
            LinearGradient(
                colors: [
                    collectionColor(for: nft).opacity(colorScheme == .dark ? 0.3 : 0.15),
                    collectionColor(for: nft).opacity(colorScheme == .dark ? 0.1 : 0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            VStack(spacing: 8) {
                // Collection initials or icon
                ZStack {
                    Circle()
                        .fill(collectionColor(for: nft).opacity(0.2))
                        .frame(width: 50, height: 50)
                    
                    Text(collectionInitials(for: nft))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(collectionColor(for: nft))
                }
                
                Text(nft.collection?.name ?? "NFT")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .lineLimit(1)
            }
        }
    }
    
    private func collectionColor(for nft: NFT) -> Color {
        // Generate consistent color based on collection name
        let name = nft.collection?.name ?? nft.contractAddress
        let hash = abs(name.hashValue)
        let colors: [Color] = [.purple, .blue, .orange, .pink, .teal, .indigo]
        return colors[hash % colors.count]
    }
    
    private func collectionInitials(for nft: NFT) -> String {
        guard let name = nft.collection?.name else { return "?" }
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1)) + String(words[1].prefix(1))
        }
        return String(name.prefix(2)).uppercased()
    }
    
    private func nftThumbnail(_ nft: NFT) -> some View {
        let imageURL = nft.imageURL.flatMap { URL(string: $0) }
        
        return VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(1, contentMode: .fill)
                case .failure:
                    nftThumbnailPlaceholder(for: nft)
                case .empty:
                    if imageURL != nil {
                        ZStack {
                            DS.Adaptive.cardBackgroundElevated
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(colorScheme == .dark ? Color(red: 1.0, green: 0.84, blue: 0.0) : .blue)
                        }
                    } else {
                        nftThumbnailPlaceholder(for: nft)
                    }
                @unknown default:
                    nftThumbnailPlaceholder(for: nft)
                }
            }
            .frame(width: 80, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DS.Adaptive.stroke, lineWidth: 1)
            )
            
            Text(nft.displayName)
                .font(.caption2)
                .foregroundColor(DS.Adaptive.textPrimary)
                .lineLimit(1)
                .frame(width: 80, alignment: .leading)
        }
    }
    
    private func nftThumbnailPlaceholder(for nft: NFT) -> some View {
        ZStack {
            LinearGradient(
                colors: [
                    collectionColor(for: nft).opacity(colorScheme == .dark ? 0.25 : 0.12),
                    collectionColor(for: nft).opacity(colorScheme == .dark ? 0.08 : 0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            Text(collectionInitials(for: nft))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(collectionColor(for: nft))
        }
    }
    
    private func defiPositionCard(_ position: DeFiPosition) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header with protocol name, type icon, value, and APY
            HStack(alignment: .top) {
                // Protocol icon and name
                HStack(spacing: 10) {
                    // Position type icon
                    ZStack {
                        Circle()
                            .fill(positionTypeColor(position.type).opacity(colorScheme == .dark ? 0.2 : 0.12))
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: position.type.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [positionTypeColor(position.type), positionTypeColor(position.type).opacity(0.7)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(position.protocol_.name)
                            .font(.headline)
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        HStack(spacing: 6) {
                            Text(position.type.displayName)
                                .font(.caption)
                                .foregroundColor(DS.Adaptive.textSecondary)
                            
                            // Chain badge
                            chainBadge(for: position.chain)
                        }
                    }
                }
                
                Spacer()
                
                // Value and APY
                VStack(alignment: .trailing, spacing: 4) {
                    Text(formatCurrency(position.valueUSD))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.green)
                    
                    // APY badge if available
                    if let apy = position.apy {
                        apyBadge(apy: apy)
                    }
                }
            }
            
            // Pool name for LP positions
            if let poolName = position.metadata?.poolName {
                HStack(spacing: 6) {
                    Image(systemName: "drop.fill")
                        .font(.caption2)
                        .foregroundColor(.blue.opacity(0.8))
                    Text(poolName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(DS.Adaptive.cardBackgroundElevated)
                )
            }
            
            // Health factor for lending positions
            if let healthFactor = position.healthFactor {
                healthFactorView(healthFactor: healthFactor)
            }
            
            // Rewards section if available
            if let rewards = position.rewardsUSD, rewards > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "gift.fill")
                        .font(.caption)
                        .foregroundColor(themedAccent)
                    
                    Text("Claimable Rewards")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    Spacer()
                    
                    Text(formatCurrency(rewards))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(themedAccent)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(themedAccent.opacity(colorScheme == .dark ? 0.1 : 0.08))
                )
            }
            
            // Token list
            if !position.tokens.isEmpty {
                Rectangle()
                    .fill(DS.Adaptive.divider)
                    .frame(height: 1)
                
                ForEach(position.tokens) { token in
                    HStack {
                        Text(token.symbol)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(DS.Adaptive.textPrimary)
                        Spacer()
                        Text(String(format: "%.4f", token.amount))
                            .font(.subheadline)
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                }
            }
        }
        .padding(16)
        .background(premiumCardBackground)
    }
    
    // MARK: - DeFi Card Helper Views
    
    private func positionTypeColor(_ type: DeFiPositionType) -> Color {
        switch type {
        case .liquidity: return .blue
        case .lending: return .green
        case .borrowing: return .orange
        case .staking: return .purple
        case .farming: return .mint
        case .vault: return .indigo
        case .claimable: return .yellow
        case .nftStaking: return .pink
        }
    }
    
    private func chainBadge(for chain: Chain) -> some View {
        HStack(spacing: 3) {
            Text(chainEmoji(for: chain))
                .font(.caption2)
            Text(chain.displayName)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundColor(chainColor(for: chain))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            Capsule()
                .fill(chainColor(for: chain).opacity(colorScheme == .dark ? 0.15 : 0.1))
        )
    }
    
    private func chainEmoji(for chain: Chain) -> String {
        switch chain {
        case .ethereum: return "Ξ"
        case .polygon: return "◈"
        case .arbitrum: return "A"
        case .optimism: return "O"
        case .base: return "B"
        case .solana: return "◎"
        case .avalanche: return "A"
        case .bsc: return "B"
        case .bitcoin: return "₿"
        case .fantom: return "F"
        case .zksync: return "Z"
        // New chains
        case .sui: return "S"
        case .aptos: return "A"
        case .ton: return "T"
        case .near: return "N"
        case .cosmos: return "⚛"
        case .polkadot: return "●"
        case .cardano: return "₳"
        case .tron: return "T"
        case .linea: return "L"
        case .scroll: return "S"
        case .manta: return "M"
        case .mantle: return "M"
        case .blast: return "B"
        case .mode: return "M"
        case .polygonZkEvm: return "◈"
        case .starknet: return "★"
        case .osmosis: return "O"
        case .injective: return "I"
        case .sei: return "S"
        }
    }
    
    private func chainColor(for chain: Chain) -> Color {
        // Use the chain's built-in brand color
        return chain.brandColor
    }
    
    private func apyBadge(apy: Double) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "percent")
                .font(.system(size: 8, weight: .bold))
            Text(String(format: "%.1f%% APY", apy))
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .foregroundColor(apyColor(apy))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(apyColor(apy).opacity(colorScheme == .dark ? 0.2 : 0.12))
        )
    }
    
    private func apyColor(_ apy: Double) -> Color {
        if apy >= 10 { return .green }
        if apy >= 5 { return .mint }
        return .blue
    }
    
    private func healthFactorView(healthFactor: Double) -> some View {
        HStack(spacing: 10) {
            Text("Health Factor")
                .font(.caption)
                .foregroundColor(DS.Adaptive.textSecondary)
            
            Spacer()
            
            // Health bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 3)
                        .fill(DS.Adaptive.cardBackgroundElevated)
                    
                    // Progress
                    RoundedRectangle(cornerRadius: 3)
                        .fill(healthFactorColor(healthFactor))
                        .frame(width: min(geo.size.width, geo.size.width * CGFloat(min(healthFactor / 3.0, 1.0))))
                }
            }
            .frame(width: 60, height: 6)
            
            Text(String(format: "%.1f", healthFactor))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(healthFactorColor(healthFactor))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(healthFactorColor(healthFactor).opacity(colorScheme == .dark ? 0.08 : 0.05))
        )
    }
    
    private func healthFactorColor(_ factor: Double) -> Color {
        if factor >= 2.0 { return .green }
        if factor >= 1.5 { return .yellow }
        return .red
    }
    
    private func defiPositionRow(_ position: DeFiPosition) -> some View {
        HStack(spacing: 12) {
            // Position type icon
            ZStack {
                Circle()
                    .fill(positionTypeColor(position.type).opacity(colorScheme == .dark ? 0.2 : 0.12))
                    .frame(width: 32, height: 32)
                
                Image(systemName: position.type.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(positionTypeColor(position.type))
            }
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(position.protocol_.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    // Small chain indicator
                    Text(chainEmoji(for: position.chain))
                        .font(.caption2)
                        .foregroundColor(chainColor(for: position.chain))
                }
                
                HStack(spacing: 6) {
                    Text(position.type.displayName)
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                    
                    // Show APY inline if available
                    if let apy = position.apy {
                        Text("•")
                            .font(.caption2)
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Text(String(format: "%.1f%% APY", apy))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(apyColor(apy))
                    }
                }
            }
            
            Spacer()
            
            Text(formatCurrency(position.valueUSD))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.green)
        }
    }
    
    // MARK: - Helpers
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = CurrencyManager.currencyCode
        if amount >= 1000 {
            formatter.maximumFractionDigits = 0
        } else {
            formatter.maximumFractionDigits = 2
        }
        return formatter.string(from: NSNumber(value: amount)) ?? "$0"
    }
    
    private func shortenAddress(_ address: String) -> String {
        guard address.count > 12 else { return address }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }
    
    private func refreshAllAsync() async {
        await multiChainVM.refreshAllWallets()
        for wallet in multiChainVM.connectedWallets {
            await nftVM.fetchNFTs(for: wallet.address, chain: wallet.chainId)
            await defiVM.fetchPositions(for: wallet.address, chain: wallet.chainId)
        }
    }
}

// MARK: - Chain Icon

struct ChainIcon: View {
    let chainId: String
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [chainColor.opacity(colorScheme == .dark ? 0.3 : 0.2), chainColor.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Circle()
                .stroke(chainColor.opacity(0.3), lineWidth: 1)
            
            Text(chainEmoji)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(chainColor)
        }
    }
    
    private var chainColor: Color {
        switch chainId {
        case "ethereum": return .blue
        case "polygon": return .purple
        case "arbitrum": return .cyan
        case "optimism": return .red
        case "base": return .blue
        case "solana": return .purple
        case "avalanche": return .red
        case "bsc": return .yellow
        default: return .gray
        }
    }
    
    private var chainEmoji: String {
        switch chainId {
        case "ethereum": return "Ξ"
        case "polygon": return "◈"
        case "arbitrum": return "A"
        case "optimism": return "O"
        case "base": return "B"
        case "solana": return "◎"
        case "avalanche": return "A"
        case "bsc": return "B"
        default: return "?"
        }
    }
}

// MARK: - Preview

#Preview {
    DeFiDashboardView()
}
