//
//  AddStockHoldingView.swift
//  CryptoSage
//
//  Created by CryptoSage on 1/19/26.
//  View for manually adding stock holdings to the portfolio.
//

import SwiftUI

struct AddStockHoldingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    // Callback when a holding is added
    let onAdd: (Holding) -> Void
    
    // Search state
    @State private var searchText = ""
    @State private var searchResults: [StockSearchResult] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    
    // Selected stock
    @State private var selectedStock: StockSearchResult?
    @State private var stockQuote: StockQuote?
    @State private var isLoadingQuote = false
    
    // Form state
    @State private var sharesText = ""
    @State private var costBasisText = ""
    @State private var purchaseDate = Date()
    @State private var useCurrentPrice = true
    
    // Validation
    @State private var showError = false
    @State private var errorMessage = ""
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom header matching app style
            CSPageHeader(title: "Add Stock", leadingAction: { dismiss() })
            
            ZStack {
                // Background
                (isDark ? Color.black : Color(UIColor.systemGroupedBackground))
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Stock Search Section
                        stockSearchSection
                        
                        // Selected Stock Card
                        if let stock = selectedStock {
                            selectedStockCard(stock)
                        }
                        
                        // Entry Form (shown after stock is selected)
                        if selectedStock != nil {
                            entryFormSection
                        }
                        
                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal)
                    .padding(.top, 16)
                }
                .scrollViewBackSwipeFix()
                
                // Add Button at bottom
                if selectedStock != nil {
                    VStack {
                        Spacer()
                        addButton
                    }
                }
            }
        }
        .background((isDark ? Color.black : Color(UIColor.systemGroupedBackground)).ignoresSafeArea())
        .navigationBarHidden(true)
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
        .alert("Unable to Add Stock", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Stock Search Section
    
    private var stockSearchSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Search Stock")
                .font(.headline)
                .foregroundStyle(isDark ? .white : .primary)
            
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                
                TextField("Search by name or ticker (e.g., AAPL)", text: $searchText)
                    .textFieldStyle(.plain)
                    .autocapitalization(.allCharacters)
                    .disableAutocorrection(true)
                    .onChange(of: searchText) { _, newValue in
                        performSearch(query: newValue)
                    }
                
                if isSearching {
                    ProgressView()
                        .scaleEffect(0.8)
                }
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        searchResults = []
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isDark ? Color.white.opacity(0.08) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
            )
            
            // Search Results
            if !searchResults.isEmpty && selectedStock == nil {
                searchResultsList
            }
        }
    }
    
    private var searchResultsList: some View {
        VStack(spacing: 0) {
            ForEach(searchResults.prefix(8)) { result in
                Button {
                    selectStock(result)
                } label: {
                    HStack(spacing: 12) {
                        // Asset type icon
                        Image(systemName: result.assetType.icon)
                            .font(.title3)
                            .foregroundStyle(result.assetType.color)
                            .frame(width: 40, height: 40)
                            .background(result.assetType.color.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.symbol)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(isDark ? .white : .primary)
                            
                            Text(result.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        if let exchange = result.exchange {
                            Text(exchange)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.secondary.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 12)
                }
                .buttonStyle(.plain)
                
                if result.id != searchResults.prefix(8).last?.id {
                    Divider()
                        .padding(.leading, 64)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isDark ? Color.white.opacity(0.05) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06), lineWidth: 1)
        )
    }
    
    // MARK: - Selected Stock Card
    
    private func selectedStockCard(_ stock: StockSearchResult) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // Stock logo (fetches real logo from StockLogoService)
                StockImageView(ticker: stock.symbol, assetType: stock.assetType, size: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(stock.symbol)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(isDark ? .white : .primary)
                        
                        Text(stock.assetType.displayName)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(stock.assetType.color)
                            .clipShape(Capsule())
                    }
                    
                    Text(stock.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                Button {
                    withAnimation {
                        selectedStock = nil
                        stockQuote = nil
                        searchText = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Price info if available
            if isLoadingQuote {
                HStack {
                    ProgressView()
                    Text("Loading price...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            } else if let quote = stockQuote {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current Price")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(formatCurrency(quote.regularMarketPrice))
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(isDark ? .white : .primary)
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Today's Change")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        let changePercent = quote.regularMarketChangePercent ?? 0
                        HStack(spacing: 4) {
                            Image(systemName: changePercent >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.caption)
                            Text(formatPercent(changePercent))
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundStyle(changePercent >= 0 ? .green : .red)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isDark ? Color.white.opacity(0.08) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(
                    LinearGradient(
                        colors: [stock.assetType.color.opacity(0.5), stock.assetType.color.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }
    
    // MARK: - Entry Form Section
    
    private var entryFormSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Holdings Details")
                .font(.headline)
                .foregroundStyle(isDark ? .white : .primary)
            
            // Number of Shares
            VStack(alignment: .leading, spacing: 8) {
                Text("Number of Shares")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                TextField("e.g., 10", text: $sharesText)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isDark ? Color.white.opacity(0.08) : Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
                    )
            }
            
            // Cost Basis
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Cost Basis (per share)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Toggle("Use current price", isOn: $useCurrentPrice)
                        .toggleStyle(.switch)
                        .scaleEffect(0.8)
                        .labelsHidden()
                    
                    Text("Current")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                if !useCurrentPrice {
                    TextField("e.g., 150.00", text: $costBasisText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(isDark ? Color.white.opacity(0.08) : Color.white)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
                        )
                } else if let quote = stockQuote {
                    Text(formatCurrency(quote.regularMarketPrice))
                        .font(.body.weight(.medium))
                        .foregroundStyle(.green)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.green.opacity(0.1))
                        )
                }
            }
            
            // Purchase Date
            VStack(alignment: .leading, spacing: 8) {
                Text("Purchase Date")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                DatePicker("", selection: $purchaseDate, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isDark ? Color.white.opacity(0.08) : Color.white)
                    )
            }
            
            // Summary
            if let shares = Double(sharesText), shares > 0 {
                summaryCard(shares: shares)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isDark ? Color.white.opacity(0.05) : Color(UIColor.secondarySystemGroupedBackground))
        )
    }
    
    private func summaryCard(shares: Double) -> some View {
        let costBasis = getCostBasis()
        let currentPrice = stockQuote?.regularMarketPrice ?? costBasis
        let totalValue = shares * currentPrice
        let totalCost = shares * costBasis
        let profitLoss = totalValue - totalCost
        
        return VStack(spacing: 12) {
            HStack {
                Text("Summary")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isDark ? .white : .primary)
                Spacer()
            }
            
            HStack {
                summaryItem(title: "Total Value", value: formatCurrency(totalValue))
                Spacer()
                summaryItem(title: "Total Cost", value: formatCurrency(totalCost))
                Spacer()
                summaryItem(
                    title: "P/L",
                    value: "\(profitLoss >= 0 ? "+" : "")\(formatCurrency(profitLoss))",
                    color: profitLoss >= 0 ? .green : .red
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isDark ? Color.white.opacity(0.05) : Color.white)
        )
    }
    
    private func summaryItem(title: String, value: String, color: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color ?? (isDark ? .white : .primary))
        }
    }
    
    // MARK: - Add Button
    
    private var addButton: some View {
        Button {
            addHolding()
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Add to Portfolio")
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [.blue, .blue.opacity(0.8)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!isFormValid)
        .opacity(isFormValid ? 1 : 0.5)
        .padding(.horizontal)
        .padding(.bottom, 20)
        .background(
            LinearGradient(
                colors: [Color.clear, isDark ? Color.black : Color(UIColor.systemGroupedBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 100)
        )
    }
    
    // MARK: - Helper Methods
    
    private func performSearch(query: String) {
        searchTask?.cancel()
        
        guard !query.isEmpty else {
            searchResults = []
            return
        }
        
        guard query.count >= 1 else { return }
        
        isSearching = true
        
        searchTask = Task {
            // Debounce
            try? await Task.sleep(nanoseconds: 300_000_000)
            
            guard !Task.isCancelled else { return }
            
            let results = await StockPriceService.shared.searchStocks(query: query)
            
            await MainActor.run {
                guard !Task.isCancelled else { return }
                searchResults = results
                isSearching = false
            }
        }
    }
    
    private func selectStock(_ stock: StockSearchResult) {
        withAnimation {
            selectedStock = stock
            searchText = stock.symbol
            searchResults = []
        }
        
        // Fetch quote
        isLoadingQuote = true
        Task {
            let quote = await StockPriceService.shared.fetchQuote(ticker: stock.symbol)
            await MainActor.run {
                stockQuote = quote
                isLoadingQuote = false
            }
        }
    }
    
    private var isFormValid: Bool {
        guard selectedStock != nil else { return false }
        guard let shares = Double(sharesText), shares > 0 else { return false }
        if !useCurrentPrice {
            guard let cost = Double(costBasisText), cost > 0 else { return false }
        } else {
            guard stockQuote != nil else { return false }
        }
        return true
    }
    
    private func getCostBasis() -> Double {
        if useCurrentPrice {
            return stockQuote?.regularMarketPrice ?? 0
        } else {
            return Double(costBasisText) ?? 0
        }
    }
    
    private func addHolding() {
        guard let stock = selectedStock,
              let shares = Double(sharesText), shares > 0 else {
            errorMessage = "Please enter a valid number of shares."
            showError = true
            return
        }
        
        let costBasis = getCostBasis()
        guard costBasis > 0 else {
            errorMessage = "Please enter a valid cost basis."
            showError = true
            return
        }
        
        let currentPrice = stockQuote?.regularMarketPrice ?? costBasis
        let dailyChange = stockQuote?.regularMarketChangePercent ?? 0
        
        let holding = Holding(
            ticker: stock.symbol,
            companyName: stock.displayName,
            shares: shares,
            currentPrice: currentPrice,
            costBasis: costBasis,
            assetType: stock.assetType,
            stockExchange: stock.exchange,
            isin: nil,
            imageUrl: nil,
            isFavorite: false,
            dailyChange: dailyChange,
            purchaseDate: purchaseDate,
            source: "manual"
        )
        
        onAdd(holding)
        dismiss()
    }
    
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = CurrencyManager.currencyCode
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
    
    private func formatPercent(_ value: Double) -> String {
        // NumberFormatter with .percent style already appends "%"
        // so do NOT add another "%" — that caused the "0.00%%" bug
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.multiplier = 1
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f%%", value)
    }
}

// MARK: - Preview

#Preview {
    AddStockHoldingView { holding in
        print("Added: \(holding.displaySymbol) - \(holding.shares) shares")
    }
}
