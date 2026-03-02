//
//  APIConfigurationView.swift
//  CryptoSage
//
//  Configuration view for DeFi API keys.
//

import SwiftUI

// MARK: - API Configuration View

struct APIConfigurationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    // SECURITY FIX: API Keys stored in Keychain instead of UserDefaults
    private static let keychainService = "CryptoSage.APIConfig"
    @State private var etherscanKey: String = ""
    @State private var alchemyKey: String = ""
    @State private var heliusKey: String = ""
    @State private var openSeaKey: String = ""
    @State private var moralisKey: String = ""
    
    // Stock market API key (stored in Keychain via APIConfig)
    @State private var finnhubKey: String = APIConfig.finnhubAPIKey
    
    @State private var showingKeyInfo = false
    @State private var selectedService: APIService?
    @State private var appeared = false
    
    private let chainRegistry = ChainRegistry.shared
    private let cardCornerRadius: CGFloat = 16
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        ZStack {
            // Premium background
            if isDark {
                FuturisticBackground()
                    .ignoresSafeArea()
            } else {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()
            }
            
            ScrollView {
                VStack(spacing: 20) {
                    // Overview Card
                    overviewCard
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(.easeOut(duration: 0.4).delay(0.1), value: appeared)
                        
                        // Blockchain Explorers Section
                        sectionCard(
                            title: "Blockchain Explorers",
                            footer: "Used for ERC20 token balances and transaction history on Ethereum and L2s."
                        ) {
                            apiKeyRow(service: .etherscan, key: $etherscanKey, placeholder: "Your Etherscan API key")
                        }
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(.easeOut(duration: 0.4).delay(0.15), value: appeared)
                        
                        // RPC Providers Section
                        sectionCard(
                            title: "RPC Providers",
                            footer: "Alchemy provides multi-chain support. Helius is required for Solana token balances."
                        ) {
                            VStack(spacing: 0) {
                                apiKeyRow(service: .alchemy, key: $alchemyKey, placeholder: "Your Alchemy API key")
                                
                                Rectangle()
                                    .fill(DS.Adaptive.divider)
                                    .frame(height: 1)
                                    .padding(.vertical, 12)
                                
                                apiKeyRow(service: .helius, key: $heliusKey, placeholder: "Your Helius API key")
                            }
                        }
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(.easeOut(duration: 0.4).delay(0.2), value: appeared)
                        
                        // NFT & DeFi Section
                        sectionCard(
                            title: "NFT & DeFi Data",
                            footer: "Higher rate limits for NFT galleries and DeFi position tracking."
                        ) {
                            VStack(spacing: 0) {
                                apiKeyRow(service: .openSea, key: $openSeaKey, placeholder: "Your OpenSea API key")
                                
                                Rectangle()
                                    .fill(DS.Adaptive.divider)
                                    .frame(height: 1)
                                    .padding(.vertical, 12)
                                
                                apiKeyRow(service: .moralis, key: $moralisKey, placeholder: "Your Moralis API key")
                            }
                        }
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(.easeOut(duration: 0.4).delay(0.25), value: appeared)
                        
                        // Stock Market Data Section
                        sectionCard(
                            title: "Stock Market Data",
                            footer: "Access S&P 500, Nasdaq 100, Dow Jones indices and real-time stock quotes."
                        ) {
                            apiKeyRow(service: .finnhub, key: $finnhubKey, placeholder: "Your Finnhub API key")
                        }
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(.easeOut(duration: 0.4).delay(0.28), value: appeared)
                        
                        // Status Section
                        statusCard
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 20)
                            .animation(.easeOut(duration: 0.4).delay(0.3), value: appeared)
                        
                        // Help Links Section
                        helpLinksCard
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 20)
                            .animation(.easeOut(duration: 0.4).delay(0.35), value: appeared)
                    }
                    .padding()
                }
                .scrollViewBackSwipeFix()
            }
            .navigationTitle("API Configuration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(isDark ? Color.black : Color(UIColor.systemGroupedBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(isDark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        applyKeys()
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(DS.Adaptive.gold)
                    }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                appeared = true
            }
            // SECURITY FIX: Load API keys from Keychain
            loadKeysFromKeychain()
        }
        // SECURITY FIX: Save keys to Keychain when they change
        .onChange(of: etherscanKey) { _, newValue in saveKeyToKeychain(newValue, account: "etherscan") }
        .onChange(of: alchemyKey) { _, newValue in saveKeyToKeychain(newValue, account: "alchemy") }
        .onChange(of: heliusKey) { _, newValue in saveKeyToKeychain(newValue, account: "helius") }
        .onChange(of: openSeaKey) { _, newValue in saveKeyToKeychain(newValue, account: "openSea") }
        .onChange(of: moralisKey) { _, newValue in saveKeyToKeychain(newValue, account: "moralis") }
        .sheet(isPresented: $showingKeyInfo) {
            if let service = selectedService {
                APIServiceInfoSheet(service: service)
            }
        }
    }
    
    // MARK: - Overview Card
    
    private var overviewCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                // Key icon with gradient background
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.25), .blue.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    
                    Image(systemName: "key.fill")
                        .font(.title2)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .blue.opacity(0.7)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("API Keys")
                        .font(.headline)
                        .foregroundColor(DS.Adaptive.textPrimary)
                    Text("Optional keys for enhanced features")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
            }
            
            Text("API keys unlock higher rate limits and additional data sources. All keys are stored locally on your device.")
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(premiumCardBackground)
    }
    
    // MARK: - Section Card
    
    private func sectionCard<Content: View>(
        title: String,
        footer: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(DS.Adaptive.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 4)
            
            // Content card
            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(premiumCardBackground)
            
            // Footer
            Text(footer)
                .font(.caption)
                .foregroundColor(DS.Adaptive.textTertiary)
                .padding(.horizontal, 4)
        }
    }
    
    // MARK: - API Key Row
    
    private func apiKeyRow(service: APIService, key: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                // Service icon with colored background
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [service.color.opacity(colorScheme == .dark ? 0.3 : 0.2), service.color.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 36, height: 36)
                    
                Image(systemName: service.icon)
                        .font(.body)
                    .foregroundColor(service.color)
                }
                
                Text(service.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Spacer()
                
                // Status indicator
                if !key.wrappedValue.isEmpty {
                    HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                        Text("Active")
                            .font(.caption2)
                        .foregroundColor(.green)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.15))
                    .clipShape(Capsule())
                }
                
                // Info button
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    selectedService = service
                    showingKeyInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.body)
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
            
            // Input field
            SecureField(placeholder, text: key)
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(DS.Adaptive.cardBackgroundElevated)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DS.Adaptive.stroke, lineWidth: 1)
                )
                .autocapitalization(.none)
                .disableAutocorrection(true)
        }
    }
    
    // MARK: - Status Card
    
    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Status")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(DS.Adaptive.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 4)
            
            VStack(spacing: 14) {
                // Configured count
                HStack {
                    Text("Configured APIs")
                        .font(.subheadline)
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Spacer()
                    
                    // Progress indicator
                    HStack(spacing: 6) {
                        ForEach(0..<APIService.allCases.count, id: \.self) { index in
                            Circle()
                                .fill(index < configuredCount ? Color.green : DS.Adaptive.stroke)
                                .frame(width: 8, height: 8)
                        }
                    }
                    
                    Text("\(configuredCount)/\(APIService.allCases.count)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(configuredCount > 0 ? .green : DS.Adaptive.textSecondary)
                }
                
                // Apply button
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    applyKeys()
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Apply Configuration")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(isDark ? .black : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: isDark
                                ? [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange]
                                : [Color(red: 0.78, green: 0.62, blue: 0.14), Color(red: 0.66, green: 0.48, blue: 0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(16)
            .background(premiumCardBackground)
        }
    }
    
    // MARK: - Help Links Card
    
    private var helpLinksCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Get API Keys")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(DS.Adaptive.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 4)
            
            VStack(spacing: 0) {
                helpLink(
                    title: "Get Etherscan API Key",
                    url: "https://etherscan.io/apis",
                    color: .blue
                )
                
                Rectangle()
                    .fill(DS.Adaptive.divider)
                    .frame(height: 1)
                
                helpLink(
                    title: "Get Alchemy API Key",
                    url: "https://dashboard.alchemy.com/",
                    color: .purple
                )
                
                Rectangle()
                    .fill(DS.Adaptive.divider)
                    .frame(height: 1)
                
                helpLink(
                    title: "Get Helius API Key",
                    url: "https://dev.helius.xyz/",
                    color: .orange
                )
                
                Rectangle()
                    .fill(DS.Adaptive.divider)
                    .frame(height: 1)
                
                helpLink(
                    title: "Get OpenSea API Key",
                    url: "https://docs.opensea.io/reference/api-keys",
                    color: .cyan
                )
                
                Rectangle()
                    .fill(DS.Adaptive.divider)
                    .frame(height: 1)
                
                helpLink(
                    title: "Get Moralis API Key",
                    url: "https://admin.moralis.io/",
                    color: .green
                )
            }
            .background(premiumCardBackground)
        }
    }
    
    private func helpLink(title: String, url: String, color: Color) -> some View {
        Link(destination: URL(string: url) ?? URL(string: "https://cryptosage.app")!) {
            HStack(spacing: 12) {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: "link")
                            .font(.caption)
                            .foregroundColor(color)
                    )
                
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Spacer()
                
                Image(systemName: "arrow.up.right.square")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
    }
    
    // MARK: - Premium Card Background
    
    private var premiumCardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
            
            // Top highlight (subtle gloss effect)
            LinearGradient(
                colors: [Color.white.opacity(colorScheme == .dark ? 0.06 : 0.25), Color.clear],
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
    
    // MARK: - Helpers
    
    private var configuredCount: Int {
        var count = 0
        if !etherscanKey.isEmpty { count += 1 }
        if !alchemyKey.isEmpty { count += 1 }
        if !heliusKey.isEmpty { count += 1 }
        if !openSeaKey.isEmpty { count += 1 }
        if !moralisKey.isEmpty { count += 1 }
        return count
    }
    
    private func applyKeys() {
        // Apply to ChainRegistry
        if !etherscanKey.isEmpty {
            chainRegistry.setAPIKey(etherscanKey, for: ChainAPIService.etherscan.rawValue)
        }
        if !alchemyKey.isEmpty {
            chainRegistry.setAPIKey(alchemyKey, for: ChainAPIService.alchemy.rawValue)
        }
        if !heliusKey.isEmpty {
            chainRegistry.setAPIKey(heliusKey, for: ChainAPIService.helius.rawValue)
        }
        if !openSeaKey.isEmpty {
            chainRegistry.setAPIKey(openSeaKey, for: "opensea")
        }
        if !moralisKey.isEmpty {
            chainRegistry.setAPIKey(moralisKey, for: ChainAPIService.moralis.rawValue)
        }
        
        // Save Finnhub API key to Keychain
        if !finnhubKey.isEmpty {
            try? APIConfig.setFinnhubAPIKey(finnhubKey)
        } else {
            APIConfig.removeFinnhubAPIKey()
        }
        
        // If user configured at least one API key, disable demo mode
        // since they're setting up for real data
        if configuredCount > 0 && DemoModeManager.shared.isDemoMode {
            DemoModeManager.shared.disableDemoMode()
        }
    }
    
    // MARK: - Keychain Helpers
    
    /// Load all API keys from Keychain
    private func loadKeysFromKeychain() {
        etherscanKey = (try? KeychainHelper.shared.read(service: Self.keychainService, account: "etherscan")) ?? ""
        alchemyKey = (try? KeychainHelper.shared.read(service: Self.keychainService, account: "alchemy")) ?? ""
        heliusKey = (try? KeychainHelper.shared.read(service: Self.keychainService, account: "helius")) ?? ""
        openSeaKey = (try? KeychainHelper.shared.read(service: Self.keychainService, account: "openSea")) ?? ""
        moralisKey = (try? KeychainHelper.shared.read(service: Self.keychainService, account: "moralis")) ?? ""
    }
    
    /// Save a key to Keychain
    private func saveKeyToKeychain(_ key: String, account: String) {
        if key.isEmpty {
            try? KeychainHelper.shared.delete(service: Self.keychainService, account: account)
        } else {
            try? KeychainHelper.shared.save(key, service: Self.keychainService, account: account)
        }
    }
}

// MARK: - API Service Info Sheet

struct APIServiceInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    let service: APIService
    
    var body: some View {
        NavigationStack {
            ZStack {
                if isDark {
                    FuturisticBackground()
                        .ignoresSafeArea()
                } else {
                    Color(UIColor.systemGroupedBackground)
                        .ignoresSafeArea()
                }
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Icon and title
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [service.color.opacity(0.3), service.color.opacity(0.1)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 80, height: 80)
                                
                                Image(systemName: service.icon)
                                    .font(.system(size: 36))
                                    .foregroundColor(service.color)
                            }
                            
                            Text(service.name)
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(DS.Adaptive.textPrimary)
                        }
                        .padding(.top, 20)
                        
                        // Info cards
                        VStack(spacing: 12) {
                            infoRow(title: "Free Tier", value: service.freeTier)
                            infoRow(title: "Best For", value: service.bestFor)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(DS.Adaptive.cardBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(DS.Adaptive.stroke, lineWidth: 1)
                                )
                        )
                        
                        // Get key button
                        Link(destination: URL(string: service.signupURL) ?? URL(string: "https://cryptosage.app")!) {
                            HStack {
                                Text("Get \(service.name) API Key")
                                Image(systemName: "arrow.up.right.square")
                            }
                            .font(.headline)
                            .foregroundColor(colorScheme == .dark ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [service.color, service.color.opacity(0.8)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("About \(service.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(isDark ? Color.black : Color(UIColor.systemGroupedBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(isDark ? .dark : .light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Text("Done")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(DS.Adaptive.gold)
                    }
                }
            }
        }
    }
    
    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(DS.Adaptive.textPrimary)
        }
    }
}

// MARK: - API Service Enum

enum APIService: String, CaseIterable, Identifiable {
    case etherscan
    case alchemy
    case helius
    case openSea
    case moralis
    case finnhub
    
    var id: String { rawValue }
    
    var name: String {
        switch self {
        case .etherscan: return "Etherscan"
        case .alchemy: return "Alchemy"
        case .helius: return "Helius"
        case .openSea: return "OpenSea"
        case .moralis: return "Moralis"
        case .finnhub: return "Finnhub"
        }
    }
    
    var icon: String {
        switch self {
        case .etherscan: return "doc.text.magnifyingglass"
        case .alchemy: return "flask"
        case .helius: return "sun.max"
        case .openSea: return "photo.stack"
        case .moralis: return "waveform.path.ecg"
        case .finnhub: return "chart.line.uptrend.xyaxis"
        }
    }
    
    var color: Color {
        switch self {
        case .etherscan: return .blue
        case .alchemy: return .purple
        case .helius: return .orange
        case .openSea: return .cyan
        case .moralis: return .green
        case .finnhub: return .teal
        }
    }
    
    var freeTier: String {
        switch self {
        case .etherscan: return "5 calls/sec"
        case .alchemy: return "300M compute/month"
        case .helius: return "1000 req/day"
        case .openSea: return "4 req/sec"
        case .moralis: return "25K req/month"
        case .finnhub: return "60 calls/min"
        }
    }
    
    var bestFor: String {
        switch self {
        case .etherscan: return "Token balances & tx history"
        case .alchemy: return "Multi-chain RPC access"
        case .helius: return "Solana token data"
        case .openSea: return "NFT metadata & pricing"
        case .moralis: return "DeFi position tracking"
        case .finnhub: return "Stock market data & indices"
        }
    }
    
    var signupURL: String {
        switch self {
        case .etherscan: return "https://etherscan.io/apis"
        case .alchemy: return "https://dashboard.alchemy.com/"
        case .helius: return "https://dev.helius.xyz/"
        case .openSea: return "https://docs.opensea.io/reference/api-keys"
        case .moralis: return "https://admin.moralis.io/"
        case .finnhub: return "https://finnhub.io/register"
        }
    }
}

// MARK: - Preview

#Preview {
    APIConfigurationView()
}
