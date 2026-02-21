//
//  NFTGalleryView.swift
//  CryptoSage
//
//  NFT gallery and collection views.
//

import SwiftUI

// MARK: - NFT Gallery View

struct NFTGalleryView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var nftService = NFTService.shared
    
    @State private var walletAddress: String = ""
    @State private var portfolio: NFTPortfolio?
    @State private var isLoading = false
    @State private var selectedNFT: NFT?
    @State private var viewMode: ViewMode = .grid
    @State private var sortOption: SortOption = .collection
    @State private var errorMessage: String?
    
    /// Theme-consistent accent color (gold in dark mode, blue in light mode)
    private var themedAccent: Color {
        colorScheme == .dark ? Color(red: 1.0, green: 0.84, blue: 0.0) : .blue
    }
    
    enum ViewMode: String, CaseIterable {
        case grid = "Grid"
        case list = "List"
    }
    
    enum SortOption: String, CaseIterable {
        case collection = "Collection"
        case chain = "Chain"
        case value = "Value"
        case recent = "Recent"
    }
    
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Wallet Input
                    walletInputSection
                    
                    if let portfolio = portfolio {
                        // Summary
                        summarySection(portfolio)
                        
                        // View Controls
                        viewControls
                        
                        // NFT Grid/List
                        nftSection(portfolio)
                    } else if !isLoading {
                        emptyState
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("NFTs")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refreshData() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading || walletAddress.isEmpty)
                }
            }
            .overlay {
                if isLoading {
                    loadingOverlay
                }
            }
            .sheet(item: $selectedNFT) { nft in
                NFTDetailView(nft: nft)
            }
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }
    
    // MARK: - Wallet Input
    
    private var walletInputSection: some View {
        HStack {
            Image(systemName: "wallet.pass.fill")
                .foregroundStyle(
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange]
                            : [.blue, .blue.opacity(0.8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            TextField("Wallet Address", text: $walletAddress)
                .textFieldStyle(.plain)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            
            if !walletAddress.isEmpty {
                Button {
                    walletAddress = ""
                    portfolio = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
            
            Button {
                Task { await loadNFTs() }
            } label: {
                Text("Load")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(colorScheme == .dark ? .black : .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange]
                                : [.blue, .blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .disabled(walletAddress.isEmpty || isLoading)
            .opacity(walletAddress.isEmpty || isLoading ? 0.6 : 1.0)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Summary Section
    
    private func summarySection(_ portfolio: NFTPortfolio) -> some View {
        VStack(spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total NFTs")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(portfolio.totalCount)")
                        .font(.title)
                        .fontWeight(.bold)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Collections")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(portfolio.collectionCount)")
                        .font(.title)
                        .fontWeight(.bold)
                }
            }
            
            if portfolio.totalEstimatedValueUSD > 0 {
                Divider()
                
                HStack {
                    Text("Estimated Value")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatCurrency(portfolio.totalEstimatedValueUSD))
                        .font(.headline)
                }
            }
            
            // Chain breakdown
            let byChain = portfolio.nftsByChain
            if byChain.count > 1 {
                HStack(spacing: 12) {
                    ForEach(Array(byChain.keys), id: \.self) { chain in
                        HStack(spacing: 4) {
                            Image(systemName: chain.iconName)
                                .foregroundColor(chain.brandColor)
                                .font(.caption)
                            Text("\(byChain[chain]?.count ?? 0)")
                                .font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(chain.brandColor.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - View Controls
    
    private var viewControls: some View {
        HStack {
            // View mode picker
            Picker("View", selection: $viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Image(systemName: mode == .grid ? "square.grid.2x2" : "list.bullet")
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 100)
            
            Spacer()
            
            // Sort picker
            Menu {
                ForEach(SortOption.allCases, id: \.self) { option in
                    Button {
                        sortOption = option
                    } label: {
                        HStack {
                            Text(option.rawValue)
                            if sortOption == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Sort: \(sortOption.rawValue)")
                    Image(systemName: "chevron.down")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - NFT Section
    
    private func nftSection(_ portfolio: NFTPortfolio) -> some View {
        let sortedNFTs = sortNFTs(portfolio.nfts)
        
        return Group {
            if viewMode == .grid {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(sortedNFTs) { nft in
                        nftGridItem(nft)
                    }
                }
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(sortedNFTs) { nft in
                        nftListItem(nft)
                    }
                }
            }
        }
    }
    
    private func nftGridItem(_ nft: NFT) -> some View {
        Button {
            selectedNFT = nft
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // Image
                AsyncImage(url: URL(string: nft.imageURL ?? "")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(1, contentMode: .fill)
                    case .failure(_):
                        Rectangle()
                            .fill(Color(.tertiarySystemGroupedBackground))
                            .overlay {
                                Image(systemName: "photo")
                                    .foregroundColor(.secondary)
                            }
                    case .empty:
                        Rectangle()
                            .fill(Color(.tertiarySystemGroupedBackground))
                            .overlay {
                                ProgressView()
                            }
                    @unknown default:
                        Rectangle()
                            .fill(Color(.tertiarySystemGroupedBackground))
                    }
                }
                .frame(height: 150)
                .cornerRadius(8)
                .clipped()
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(nft.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    
                    HStack {
                        Image(systemName: nft.chain.iconName)
                            .font(.caption2)
                            .foregroundColor(nft.chain.brandColor)
                        
                        if let collection = nft.collection {
                            Text(collection.name)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(8)
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
    
    private func nftListItem(_ nft: NFT) -> some View {
        Button {
            selectedNFT = nft
        } label: {
            HStack(spacing: 12) {
                // Image
                AsyncImage(url: URL(string: nft.imageURL ?? "")) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(1, contentMode: .fill)
                    default:
                        Rectangle()
                            .fill(Color(.tertiarySystemGroupedBackground))
                            .overlay {
                                Image(systemName: "photo")
                                    .foregroundColor(.secondary)
                            }
                    }
                }
                .frame(width: 60, height: 60)
                .cornerRadius(8)
                .clipped()
                
                // Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(nft.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    if let collection = nft.collection {
                        Text(collection.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Image(systemName: nft.chain.iconName)
                            .font(.caption2)
                            .foregroundColor(nft.chain.brandColor)
                        Text(nft.chain.displayName)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                if let value = nft.estimatedValueUSD {
                    Text(formatCurrency(value))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.stack")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("Enter Wallet Address")
                .font(.headline)
            
            Text("Paste an ETH, Polygon, or SOL wallet address to view NFTs.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
    }
    
    // MARK: - Loading Overlay
    
    private var loadingOverlay: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(themedAccent)
            
            Text("Loading NFTs...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Actions
    
    private func loadNFTs() async {
        guard !walletAddress.isEmpty else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            portfolio = try await nftService.fetchNFTs(address: walletAddress)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func refreshData() async {
        nftService.clearCache()
        await loadNFTs()
    }
    
    // MARK: - Helpers
    
    private func sortNFTs(_ nfts: [NFT]) -> [NFT] {
        switch sortOption {
        case .collection:
            return nfts.sorted { ($0.collection?.name ?? "") < ($1.collection?.name ?? "") }
        case .chain:
            return nfts.sorted { $0.chain.displayName < $1.chain.displayName }
        case .value:
            return nfts.sorted { ($0.estimatedValueUSD ?? 0) > ($1.estimatedValueUSD ?? 0) }
        case .recent:
            return nfts.sorted { ($0.lastTransferDate ?? .distantPast) > ($1.lastTransferDate ?? .distantPast) }
        }
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = CurrencyManager.currencyCode
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }
}

// MARK: - NFT Detail View

struct NFTDetailView: View {
    let nft: NFT
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Image
                    AsyncImage(url: URL(string: nft.imageURL ?? "")) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        case .failure(_):
                            Rectangle()
                                .fill(Color(.tertiarySystemGroupedBackground))
                                .aspectRatio(1, contentMode: .fit)
                                .overlay {
                                    Image(systemName: "photo")
                                        .font(.system(size: 48))
                                        .foregroundColor(.secondary)
                                }
                        case .empty:
                            Rectangle()
                                .fill(Color(.tertiarySystemGroupedBackground))
                                .aspectRatio(1, contentMode: .fit)
                                .overlay {
                                    ProgressView()
                                }
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .cornerRadius(16)
                    
                    // Details
                    VStack(alignment: .leading, spacing: 16) {
                        // Name & Collection
                        VStack(alignment: .leading, spacing: 8) {
                            Text(nft.displayName)
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            if let collection = nft.collection {
                                HStack {
                                    Text(collection.name)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    
                                    if collection.isVerified {
                                        Image(systemName: "checkmark.seal.fill")
                                            .foregroundColor(.blue)
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                        
                        // Chain & Standard
                        HStack {
                            Label(nft.chain.displayName, systemImage: nft.chain.iconName)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(nft.chain.brandColor.opacity(0.1))
                                .foregroundColor(nft.chain.brandColor)
                                .cornerRadius(8)
                            
                            Text(nft.tokenStandard.displayName)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(.tertiarySystemGroupedBackground))
                                .cornerRadius(8)
                        }
                        
                        // Description
                        if let description = nft.description, !description.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Description")
                                    .font(.headline)
                                
                                Text(description)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        // Attributes
                        if !nft.attributes.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Attributes")
                                    .font(.headline)
                                
                                LazyVGrid(columns: [
                                    GridItem(.flexible()),
                                    GridItem(.flexible())
                                ], spacing: 8) {
                                    ForEach(nft.attributes) { attr in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(attr.traitType)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text(attr.value)
                                                .font(.caption)
                                                .fontWeight(.medium)
                                            
                                            if let rarity = attr.rarity {
                                                Text("\(String(format: "%.1f", rarity))% have this")
                                                    .font(.caption2)
                                                    .foregroundColor(.blue)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(8)
                                        .background(Color(.tertiarySystemGroupedBackground))
                                        .cornerRadius(8)
                                    }
                                }
                            }
                        }
                        
                        // Contract Info
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Contract")
                                .font(.headline)
                            
                            HStack {
                                Text(formatAddress(nft.contractAddress))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Button {
                                    // SECURITY: Auto-clear clipboard after 60s
                                    SecurityManager.shared.secureCopy(nft.contractAddress)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption)
                                }
                            }
                            
                            if let url = nft.explorerURL {
                                Link(destination: url) {
                                    Label("View on Explorer", systemImage: "arrow.up.right.square")
                                        .font(.caption)
                                }
                            }
                        }
                    }
                    .padding()
                }
                .padding()
            }
            .navigationTitle("NFT Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Text("Done")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(BrandColors.goldBase)
                    }
                }
            }
        }
    }
    
    private func formatAddress(_ address: String) -> String {
        guard address.count > 16 else { return address }
        return "\(address.prefix(8))...\(address.suffix(6))"
    }
}

// MARK: - Preview

#Preview {
    NFTGalleryView()
}
