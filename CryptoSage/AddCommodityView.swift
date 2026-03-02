//
//  AddCommodityView.swift
//  CryptoSage
//
//  Created by CryptoSage on 1/30/26.
//  View for manually adding commodity holdings (gold, silver, oil, etc.) to the portfolio.
//

import SwiftUI

struct AddCommodityView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    // Callback when a holding is added
    let onAdd: (Holding) -> Void
    
    // Selected commodity
    @State private var selectedCommodity: CommodityInfo?
    @State private var currentPrice: Double = 0
    @State private var isLoadingPrice: Bool = false
    
    // Form state
    @State private var quantityText = ""
    @State private var costBasisText = ""
    @State private var purchaseDate = Date()
    @State private var useCurrentPrice = true
    
    // Filter state
    @State private var selectedType: CommodityType? = nil
    @State private var searchText = ""
    
    // Validation
    @State private var showError = false
    @State private var errorMessage = ""
    
    private var isDark: Bool { colorScheme == .dark }
    
    // Filtered commodities based on search and type
    private var filteredCommodities: [CommodityInfo] {
        var commodities = CommoditySymbolMapper.allCommodities
        
        if let type = selectedType {
            commodities = commodities.filter { $0.type == type }
        }
        
        if !searchText.isEmpty {
            commodities = commodities.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.displaySymbol.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return commodities
    }
    
    // Computed values
    private var quantity: Double {
        Double(quantityText) ?? 0
    }
    
    private var totalValue: Double {
        quantity * currentPrice
    }
    
    private var costBasis: Double {
        if useCurrentPrice {
            return totalValue
        }
        return Double(costBasisText) ?? totalValue
    }
    
    private var isValid: Bool {
        selectedCommodity != nil && quantity > 0 && currentPrice > 0
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom header matching app style
            // FIX: Back button is context-aware — if a commodity is selected, go back to
            // the commodity selection list first instead of dismissing the entire view.
            CSPageHeader(title: "Add Commodity", leadingAction: {
                if selectedCommodity != nil {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selectedCommodity = nil
                        currentPrice = 0
                        quantityText = ""
                        costBasisText = ""
                        useCurrentPrice = true
                    }
                } else {
                    dismiss()
                }
            })
            
            ZStack {
                // Background
                (isDark ? Color.black : Color(UIColor.systemGroupedBackground))
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Commodity Selection
                        if selectedCommodity == nil {
                            commoditySelectionSection
                        } else {
                            selectedCommodityCard
                            entryFormSection
                        }
                        
                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal)
                    .padding(.top, 16)
                }
                .scrollViewBackSwipeFix()
                
                // Add Button at bottom
                if selectedCommodity != nil {
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
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }
    
    // MARK: - Commodity Selection Section
    
    private var commoditySelectionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Search bar
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                
                TextField("Search commodities...", text: $searchText)
                    .textFieldStyle(.plain)
                
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
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
            
            // Type filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    typeFilterPill(nil, title: "All")
                    ForEach(CommodityType.allCases) { type in
                        typeFilterPill(type, title: type.rawValue)
                    }
                }
            }
            
            // Commodities list
            VStack(spacing: 0) {
                ForEach(filteredCommodities) { commodity in
                    Button {
                        selectCommodity(commodity)
                    } label: {
                        commodityRow(commodity)
                    }
                    .buttonStyle(.plain)
                    
                    if commodity.id != filteredCommodities.last?.id {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isDark ? Color.white.opacity(0.06) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
            )
        }
    }
    
    private func typeFilterPill(_ type: CommodityType?, title: String) -> some View {
        let isSelected = selectedType == type
        
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedType = type
            }
        } label: {
            HStack(spacing: 4) {
                if let type = type {
                    Image(systemName: type.icon)
                        .font(.system(size: 12))
                }
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(isSelected ? TintedChipStyle.selectedText(isDark: isDark) : (isDark ? .white : .primary))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? TintedChipStyle.selectedBackground(isDark: isDark) : (isDark ? Color.white.opacity(0.1) : Color.gray.opacity(0.12)))
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? TintedChipStyle.selectedStroke(isDark: isDark) : Color.clear, lineWidth: 1)
            )
        }
    }
    
    private func commodityRow(_ commodity: CommodityInfo) -> some View {
        HStack(spacing: 12) {
            // Distinctive commodity icon
            CommodityIconView(commodityId: commodity.id, size: 44)
                .allowsHitTesting(false)
            
            // Name and symbol
            VStack(alignment: .leading, spacing: 2) {
                Text(commodity.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isDark ? .white : .primary)
                
                HStack(spacing: 6) {
                    Text(commodity.displaySymbol)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    
                    // Coinbase indicator
                    if commodity.hasCoinbaseData {
                        Text("Coinbase")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
            }
            
            Spacer()
            
            // Unit
            Text("per \(commodity.unit)")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }
    
    private func commodityColor(for type: CommodityType) -> Color {
        if isDark {
            switch type {
            case .preciousMetal: return .yellow
            case .industrialMetal: return .orange
            case .energy: return .blue
            case .agriculture: return .green
            case .livestock: return .brown
            }
        } else {
            // Deeper tones in light mode for readable white text on colored badges
            switch type {
            case .preciousMetal: return Color(red: 0.75, green: 0.60, blue: 0.08)
            case .industrialMetal: return Color(red: 0.80, green: 0.50, blue: 0.10)
            case .energy: return Color(red: 0.15, green: 0.40, blue: 0.75)
            case .agriculture: return Color(red: 0.13, green: 0.55, blue: 0.13)
            case .livestock: return Color(red: 0.50, green: 0.35, blue: 0.18)
            }
        }
    }
    
    // MARK: - Selected Commodity Card
    
    private var selectedCommodityCard: some View {
        VStack(spacing: 12) {
            if let commodity = selectedCommodity {
            HStack(spacing: 12) {
                // Distinctive commodity icon
                CommodityIconView(commodityId: commodity.id, size: 50)

                VStack(alignment: .leading, spacing: 4) {
                    Text(commodity.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(isDark ? .white : .primary)

                    HStack(spacing: 6) {
                        Text(commodity.displaySymbol)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(commodity.type.rawValue)
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(commodityColor(for: commodity.type).opacity(0.8))
                            .clipShape(Capsule())
                    }
                }
                
                Spacer()
                
                // Change button
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        selectedCommodity = nil
                        currentPrice = 0
                        quantityText = ""
                        costBasisText = ""
                        useCurrentPrice = true
                    }
                } label: {
                    Text("Change")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(DS.Adaptive.gold)
                }
            }
            
            Divider()
            
            // Current price
            HStack {
                Text("Current Price")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if isLoadingPrice {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if currentPrice > 0 {
                    Text(formatCurrency(currentPrice))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isDark ? .white : .primary)
                    Text("/ \(commodity.unit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Unavailable")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            } // end if let commodity
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isDark ? Color.white.opacity(0.06) : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Entry Form Section
    
    private var entryFormSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enter Details")
                .font(.headline)
                .foregroundStyle(isDark ? .white : .primary)
            
            VStack(spacing: 12) {
                // Quantity input
                formField(
                    title: "Quantity (\(selectedCommodity?.unit ?? "units"))",
                    placeholder: "e.g., 10",
                    text: $quantityText,
                    keyboardType: .decimalPad
                )
                
                Divider()
                
                // Cost basis toggle
                Toggle(isOn: $useCurrentPrice) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use Current Price")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(isDark ? .white : .primary)
                        
                        Text("Cost basis will be calculated at today's price")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(DS.Adaptive.gold)
                .padding(.vertical, 4)
                
                if !useCurrentPrice {
                    Divider()
                    
                    // Manual cost basis
                    formField(
                        title: "Total Cost Basis (USD)",
                        placeholder: "e.g., 20000",
                        text: $costBasisText,
                        keyboardType: .decimalPad
                    )
                }
                
                Divider()
                
                // Purchase date
                DatePicker(
                    "Purchase Date",
                    selection: $purchaseDate,
                    displayedComponents: .date
                )
                .font(.subheadline.weight(.medium))
                .foregroundStyle(isDark ? .white : .primary)
                .tint(DS.Adaptive.gold)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isDark ? Color.white.opacity(0.06) : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.08), lineWidth: 1)
            )
            
            // Summary
            if quantity > 0 && currentPrice > 0 {
                summaryCard
            }
        }
    }
    
    private func formField(title: String, placeholder: String, text: Binding<String>, keyboardType: UIKeyboardType = .default) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            
            TextField(placeholder, text: text)
                .font(.system(size: 17))
                .foregroundStyle(isDark ? .white : .primary)
                .keyboardType(keyboardType)
        }
    }
    
    private var summaryCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Summary")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isDark ? .white : .primary)
                Spacer()
            }
            
            HStack {
                Text("\(formatQuantity(quantity)) \(selectedCommodity?.unit ?? "units") of \(selectedCommodity?.name ?? "Commodity")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            
            Divider()
            
            HStack {
                Text("Total Value")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatCurrency(totalValue))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isDark ? .white : .primary)
            }
            
            HStack {
                Text("Cost Basis")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formatCurrency(costBasis))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(DS.Adaptive.gold.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(DS.Adaptive.gold.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Add Button
    
    private var addButton: some View {
        Button {
            addCommodityHolding()
        } label: {
            HStack {
                Image(systemName: "plus.circle.fill")
                Text("Add to Portfolio")
            }
            .font(.headline)
            .foregroundColor(isDark ? .black : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isValid
                        ? (isDark
                            ? AnyShapeStyle(LinearGradient(colors: [BrandColors.goldLight, BrandColors.goldBase], startPoint: .top, endPoint: .bottom))
                            : AnyShapeStyle(LinearGradient(colors: [Color(red: 0.78, green: 0.62, blue: 0.14), Color(red: 0.60, green: 0.45, blue: 0.08)], startPoint: .top, endPoint: .bottom)))
                        : AnyShapeStyle(Color.gray.opacity(0.3)))
            )
        }
        .disabled(!isValid)
        .padding(.horizontal)
        .padding(.bottom, 16)
        .background(
            LinearGradient(
                colors: [
                    (isDark ? Color.black : Color(UIColor.systemGroupedBackground)).opacity(0),
                    (isDark ? Color.black : Color(UIColor.systemGroupedBackground))
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 100)
            .offset(y: -50)
            .allowsHitTesting(false)
        )
    }
    
    // MARK: - Actions
    
    private func selectCommodity(_ commodity: CommodityInfo) {
        withAnimation(.easeInOut(duration: 0.3)) {
            selectedCommodity = commodity
        }
        
        // Fetch current price
        fetchPrice(for: commodity)
    }
    
    private func fetchPrice(for commodity: CommodityInfo) {
        isLoadingPrice = true
        
        Task {
            // Try Coinbase first for precious metals
            if let coinbaseSymbol = commodity.coinbaseSymbol {
                if let price = await CoinbaseService.shared.fetchSpotPrice(coin: coinbaseSymbol), price > 0 {
                    await MainActor.run {
                        currentPrice = price
                        isLoadingPrice = false
                    }
                    return
                }
            }
            
            // Fallback to Yahoo Finance
            if let quote = await StockPriceService.shared.fetchQuote(ticker: commodity.yahooSymbol) {
                await MainActor.run {
                    currentPrice = quote.regularMarketPrice
                    isLoadingPrice = false
                }
                return
            }
            
            await MainActor.run {
                isLoadingPrice = false
            }
        }
    }
    
    private func addCommodityHolding() {
        guard let commodity = selectedCommodity, isValid else {
            errorMessage = "Please fill in all required fields."
            showError = true
            return
        }
        
        // Create the holding using stock/ETF initializer (commodities use similar structure)
        let holding = Holding(
            id: UUID(),
            ticker: commodity.coinbaseSymbol ?? commodity.yahooSymbol,
            companyName: commodity.name,
            shares: quantity,
            currentPrice: currentPrice,
            costBasis: costBasis,
            assetType: .commodity,
            stockExchange: nil,
            isin: nil,
            imageUrl: nil,
            isFavorite: false,
            dailyChange: 0,
            purchaseDate: purchaseDate,
            source: nil
        )
        
        // Notify via callback
        onAdd(holding)
        
        // Dismiss the view
        dismiss()
    }
    
    // MARK: - Formatters
    
    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = CurrencyManager.currencyCode
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }
    
    private func formatQuantity(_ value: Double) -> String {
        if value == floor(value) {
            return String(format: "%.0f", value)
        } else {
            return String(format: "%.4f", value)
        }
    }
}

// MARK: - Preview

#Preview("Add Commodity") {
    AddCommodityView { holding in
        print("Added commodity: \(holding.coinName)")
    }
    .preferredColorScheme(.dark)
}
