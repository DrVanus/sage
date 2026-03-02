import SwiftUI
import UIKit

// MARK: - Section Filter

/// Filter to show specific sections in ExchangesView
enum ExchangeSectionFilter {
    case all        // Show everything
    case oauth      // Quick Connect only (Coinbase, Kraken, Gemini)
    case apiKey     // API Key exchanges only (Binance, KuCoin, etc.)
    case wallets    // Wallet address tracking only
    
    var title: String {
        switch self {
        case .all: return "Exchanges & Wallets"
        case .oauth: return "Quick Connect"
        case .apiKey: return "Exchanges"
        case .wallets: return "Track Wallets"
        }
    }
    
    var subtitle: String? {
        switch self {
        case .all: return nil
        case .oauth: return "One-click secure login"
        case .apiKey: return "Connect with read-only API keys"
        case .wallets: return "Just paste your wallet address"
        }
    }
}

// MARK: - ExchangeItem Model

struct ExchangeItem: Identifiable {
    let id = UUID()
    let name: String
    let type: ExchangeType
    let connectionMethod: ConnectionType
    
    enum ExchangeType: String {
        case exchange = "exchange"
        case wallet = "wallet"
    }
    
    // Initialize with auto-detected connection method
    init(name: String, type: ExchangeType) {
        self.name = name
        self.type = type
        
        // Determine connection method based on exchange name
        if let info = ExchangeRegistry.get(name: name) {
            self.connectionMethod = info.connectionType
        } else {
            // Default based on type
            self.connectionMethod = type == .wallet ? .walletAddress : .apiKey
        }
    }
    
    // Initialize with explicit connection method
    init(name: String, type: ExchangeType, connectionMethod: ConnectionType) {
        self.name = name
        self.type = type
        self.connectionMethod = connectionMethod
    }
}

// MARK: - Sample Data (Organized by Connection Method)

// OAuth Exchanges - One-click connect
private let oauthExchanges: [ExchangeItem] = [
    ExchangeItem(name: "Coinbase", type: .exchange, connectionMethod: .oauth),
    ExchangeItem(name: "Kraken", type: .exchange, connectionMethod: .oauth),
    ExchangeItem(name: "Gemini", type: .exchange, connectionMethod: .oauth)
]

// API Key Exchanges - Manual key entry
// Note: Only exchanges with working adapters are listed
private let apiKeyExchanges: [ExchangeItem] = [
    ExchangeItem(name: "Binance", type: .exchange, connectionMethod: .apiKey),
    ExchangeItem(name: "Binance US", type: .exchange, connectionMethod: .apiKey),
    ExchangeItem(name: "KuCoin", type: .exchange, connectionMethod: .apiKey),
    ExchangeItem(name: "Bybit", type: .exchange, connectionMethod: .apiKey),
    ExchangeItem(name: "OKX", type: .exchange, connectionMethod: .apiKey),
    ExchangeItem(name: "Gate.io", type: .exchange, connectionMethod: .apiKey),
    ExchangeItem(name: "MEXC", type: .exchange, connectionMethod: .apiKey),
    ExchangeItem(name: "HTX", type: .exchange, connectionMethod: .apiKey),
    ExchangeItem(name: "Bitstamp", type: .exchange, connectionMethod: .apiKey),
    ExchangeItem(name: "Crypto.com", type: .exchange, connectionMethod: .apiKey),
    ExchangeItem(name: "Bitget", type: .exchange, connectionMethod: .apiKey),
    ExchangeItem(name: "Bitfinex", type: .exchange, connectionMethod: .apiKey)
]

// All exchanges combined
private let sampleExchanges: [ExchangeItem] = oauthExchanges + apiKeyExchanges

// Wallet Address Tracking - Just paste address
private let sampleWallets: [ExchangeItem] = [
    ExchangeItem(name: "Ethereum Wallet", type: .wallet, connectionMethod: .walletAddress),
    ExchangeItem(name: "Bitcoin Wallet", type: .wallet, connectionMethod: .walletAddress),
    ExchangeItem(name: "Solana Wallet", type: .wallet, connectionMethod: .walletAddress),
    ExchangeItem(name: "Polygon Wallet", type: .wallet, connectionMethod: .walletAddress),
    ExchangeItem(name: "Arbitrum Wallet", type: .wallet, connectionMethod: .walletAddress),
    ExchangeItem(name: "Base Wallet", type: .wallet, connectionMethod: .walletAddress),
    ExchangeItem(name: "Avalanche Wallet", type: .wallet, connectionMethod: .walletAddress),
    ExchangeItem(name: "BNB Chain Wallet", type: .wallet, connectionMethod: .walletAddress),
    ExchangeItem(name: "MetaMask", type: .wallet, connectionMethod: .walletAddress),
    ExchangeItem(name: "Trust Wallet", type: .wallet, connectionMethod: .walletAddress),
    ExchangeItem(name: "Ledger Live", type: .wallet, connectionMethod: .walletAddress)
]

// MARK: - ExchangesView

struct ExchangesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    // Section filter - defaults to showing all
    let filter: ExchangeSectionFilter
    
    // Toggle search bar visibility and hold search text
    @State private var showSearch = false
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    
    // Two-column grid layout with comfortable spacing
    private let columns = [
        GridItem(.flexible(minimum: 140), spacing: 20),
        GridItem(.flexible(minimum: 140), spacing: 20)
    ]
    
    // Initializer with default filter
    init(filter: ExchangeSectionFilter = .all) {
        self.filter = filter
    }
    
    // Filtered lists based on search and section filter
    private var filteredOAuthExchanges: [ExchangeItem] {
        guard filter == .all || filter == .oauth else { return [] }
        return oauthExchanges.filter {
            searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private var filteredAPIExchanges: [ExchangeItem] {
        guard filter == .all || filter == .apiKey else { return [] }
        return apiKeyExchanges.filter {
            searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private var filteredWallets: [ExchangeItem] {
        guard filter == .all || filter == .wallets else { return [] }
        return sampleWallets.filter {
            searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    // Check if showing only one section (for simplified header)
    private var isSingleSection: Bool {
        filter != .all
    }
    
    var body: some View {
        ZStack {
            DS.Adaptive.background
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // MARK: - Custom Top Bar
                HStack {
                    CSNavButton(
                        icon: "chevron.left",
                        action: { dismiss() }
                    )
                    
                    Spacer()
                    
                    Text(filter.title)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation {
                            showSearch.toggle()
                            if !showSearch { searchText = "" }
                        }
                    }) {
                        Image(systemName: showSearch ? "xmark.circle.fill" : "magnifyingglass")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)
                .background(DS.Adaptive.backgroundSecondary)
                
                // MARK: - Search Bar
                if showSearch {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(DS.Adaptive.textTertiary)
                        TextField("Search", text: $searchText)
                            .textFieldStyle(.plain)
                            .focused($isSearchFocused)
                            .submitLabel(.search)
                            .foregroundColor(DS.Adaptive.textPrimary)
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(DS.Adaptive.textSecondary)
                            }
                        }
                    }
                    .padding(10)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isSearchFocused = true
                    }
                    .background(DS.Adaptive.chipBackground)
                    .cornerRadius(8)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        // Auto-focus when search bar appears
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isSearchFocused = true
                        }
                    }
                }
                
                // MARK: - Main Scroll Content
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        
                        // MARK: - Subtitle for filtered views
                        if isSingleSection, let subtitle = filter.subtitle {
                            Text(subtitle)
                                .font(.subheadline)
                                .foregroundColor(DS.Adaptive.textSecondary)
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                        }
                        
                        // MARK: - Quick Connect Section (OAuth)
                        if !filteredOAuthExchanges.isEmpty {
                            if !isSingleSection {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "bolt.fill")
                                            .foregroundColor(.green)
                                        Text("Quick Connect")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(DS.Adaptive.textPrimary)
                                    }
                                    .padding(.leading, 16)
                                    .padding(.top, 16)
                                    
                                    Text("One-click secure login")
                                        .font(.caption)
                                        .foregroundColor(DS.Adaptive.textSecondary)
                                        .padding(.leading, 16)
                                }
                            }
                            
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(filteredOAuthExchanges) { exchange in
                                    ExchangeGridCard(item: exchange)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, isSingleSection ? 8 : 0)
                        }
                        
                        // MARK: - API Key Exchanges Section
                        if !filteredAPIExchanges.isEmpty {
                            if !isSingleSection {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "key.fill")
                                            .foregroundColor(.orange)
                                        Text("Exchanges")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(DS.Adaptive.textPrimary)
                                    }
                                    .padding(.leading, 16)
                                    .padding(.top, 8)
                                    
                                    Text("Connect with read-only API keys")
                                        .font(.caption)
                                        .foregroundColor(DS.Adaptive.textSecondary)
                                        .padding(.leading, 16)
                                }
                            }
                            
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(filteredAPIExchanges) { exchange in
                                    ExchangeGridCard(item: exchange)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, isSingleSection ? 8 : 0)
                        }
                        
                        // MARK: - Wallets Section
                        if !filteredWallets.isEmpty {
                            if !isSingleSection {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "wallet.pass.fill")
                                            .foregroundColor(.purple)
                                        Text("Wallets")
                                            .font(.headline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(DS.Adaptive.textPrimary)
                                    }
                                    .padding(.leading, 16)
                                    .padding(.top, 8)
                                    
                                    Text("Track by wallet address - no keys needed")
                                        .font(.caption)
                                        .foregroundColor(DS.Adaptive.textSecondary)
                                        .padding(.leading, 16)
                                }
                            }
                            
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(filteredWallets) { wallet in
                                    ExchangeGridCard(item: wallet)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, isSingleSection ? 8 : 0)
                        }
                        
                        // Empty state for filtered views with no results
                        if filteredOAuthExchanges.isEmpty && filteredAPIExchanges.isEmpty && filteredWallets.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 40))
                                    .foregroundColor(DS.Adaptive.textTertiary)
                                
                                Text("No results found")
                                    .font(.headline)
                                    .foregroundColor(DS.Adaptive.textSecondary)
                                
                                if !searchText.isEmpty {
                                    Text("Try a different search term")
                                        .font(.subheadline)
                                        .foregroundColor(DS.Adaptive.textTertiary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                        }
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.bottom, 40)
                }
                // PERFORMANCE FIX v21: UIKit scroll bridge for snappier deceleration + animation freeze
                .withUIKitScrollBridge()
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        // NAVIGATION: Enable native iOS pop gesture + custom edge swipe
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
    }
}

// MARK: - ExchangeGridCard

struct ExchangeGridCard: View {
    let item: ExchangeItem
    @State private var isPressed = false
    @ObservedObject private var accountsManager = ConnectedAccountsManager.shared
    @Environment(\.colorScheme) private var colorScheme
    
    private var isConnected: Bool {
        accountsManager.isConnected(exchangeName: item.name)
    }
    
    /// Connection method badge color
    private var connectionBadgeColor: Color {
        switch item.connectionMethod {
        case .oauth:
            return Color.green
        case .apiKey:
            return Color.orange
        case .walletAddress:
            return Color.purple
        case .threeCommas:
            return Color.cyan
        }
    }
    
    /// Connection method icon
    private var connectionIcon: String {
        switch item.connectionMethod {
        case .oauth:
            return "bolt.fill"
        case .apiKey:
            return "key.fill"
        case .walletAddress:
            return "wallet.pass.fill"
        case .threeCommas:
            return "link"
        }
    }
    
    var body: some View {
        NavigationLink(destination: ExchangeConnectionView(
            exchangeName: item.name,
            connectionMethod: item.connectionMethod
        )) {
            VStack(spacing: 0) {
                // Top section with logo
                ZStack {
                    // Gradient background for logo area - adaptive
                    DS.Adaptive.cardBackground
                    
                    VStack(spacing: 8) {
                        // Logo
                        ExchangeLogoView(name: item.name, size: 44)
                        
                        // Exchange name
                        Text(item.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(.vertical, 16)
                    
                    // Connection method badge (top-right corner)
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: connectionIcon)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(connectionBadgeColor)
                                .padding(4)
                                .background(connectionBadgeColor.opacity(0.2))
                                .clipShape(Circle())
                        }
                        Spacer()
                    }
                    .padding(8)
                }
                
                // Bottom section with connect button
                ZStack {
                    DS.Adaptive.chipBackground
                    
                    HStack {
                        if isConnected {
                            // Connected indicator
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 6, height: 6)
                                Text("Connected")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.green)
                            }
                        } else {
                            // Connect button with method hint
                            Text(item.connectionMethod == .oauth ? "Login" : "Connect")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(DS.Adaptive.textPrimary)
                        }
                    }
                    .padding(.vertical, 10)
                }
            }
            .frame(height: 130)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(DS.Adaptive.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isConnected ? Color.green.opacity(0.4) : DS.Adaptive.stroke,
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(ExchangeCardButtonStyle())
    }
}

// MARK: - Button Style for Card Press Effect

struct ExchangeCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Preview

struct ExchangesView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            NavigationStack {
                ExchangesView(filter: .all)
            }
            .previewDisplayName("All")
            
            NavigationStack {
                ExchangesView(filter: .oauth)
            }
            .previewDisplayName("OAuth Only")
            
            NavigationStack {
                ExchangesView(filter: .wallets)
            }
            .previewDisplayName("Wallets Only")
        }
    }
}
