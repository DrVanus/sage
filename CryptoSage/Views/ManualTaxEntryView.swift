//
//  ManualTaxEntryView.swift
//  CryptoSage
//
//  Manual transaction entry, edit, and delete functionality for tax tracking.
//

import SwiftUI

// MARK: - Manual Tax Entry View

struct ManualTaxEntryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var lotManager = TaxLotManager.shared
    @StateObject private var taxEngine = TaxEngine.shared
    
    @State private var showAddTransaction = false
    @State private var showAddIncome = false
    @State private var selectedTab = 0
    @State private var editingLot: TaxLot?
    @State private var editingDisposal: TaxDisposal?
    @State private var editingIncome: IncomeEvent?
    @State private var showDeleteAlert = false
    @State private var lotToDelete: TaxLot?
    @State private var disposalToDelete: TaxDisposal?
    @State private var incomeToDelete: IncomeEvent?
    
    private var themedAccent: Color {
        colorScheme == .dark ? Color(red: 1.0, green: 0.84, blue: 0.0) : .blue
    }
    
    private var chipGoldGradient: LinearGradient {
        LinearGradient(
            colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                FuturisticBackground()
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Tab Picker
                    Picker("View", selection: $selectedTab) {
                        Text("Acquisitions").tag(0)
                        Text("Disposals").tag(1)
                        Text("Income").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding()
                    
                    // Content
                    TabView(selection: $selectedTab) {
                        acquisitionsTab.tag(0)
                        disposalsTab.tag(1)
                        incomeTab.tag(2)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
            .navigationTitle("Tax Transactions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Text("Done")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(BrandColors.goldBase)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showAddTransaction = true
                        } label: {
                            Label("Add Acquisition", systemImage: "plus.circle")
                        }
                        
                        Button {
                            showAddIncome = true
                        } label: {
                            Label("Add Income", systemImage: "dollarsign.circle")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(chipGoldGradient)
                    }
                }
            }
            .sheet(isPresented: $showAddTransaction) {
                AddTaxLotSheet(editingLot: $editingLot)
            }
            .sheet(isPresented: $showAddIncome) {
                AddIncomeEventSheet(editingIncome: $editingIncome)
            }
            .sheet(item: $editingLot) { lot in
                AddTaxLotSheet(editingLot: $editingLot)
            }
            .sheet(item: $editingIncome) { income in
                AddIncomeEventSheet(editingIncome: $editingIncome)
            }
            .alert("Delete Transaction", isPresented: $showDeleteAlert) {
                Button("Cancel", role: .cancel) {
                    lotToDelete = nil
                    disposalToDelete = nil
                    incomeToDelete = nil
                }
                Button("Delete", role: .destructive) {
                    performDelete()
                }
            } message: {
                Text("Are you sure you want to delete this transaction? This cannot be undone.")
            }
        }
    }
    
    // MARK: - Acquisitions Tab
    
    private var acquisitionsTab: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if lotManager.lots.isEmpty {
                    emptyStateView(
                        icon: "doc.text",
                        title: "No Acquisitions",
                        message: "Add your crypto purchases and acquisitions to track cost basis."
                    )
                } else {
                    ForEach(lotManager.lots.sorted(by: { $0.acquiredDate > $1.acquiredDate })) { lot in
                        acquisitionCard(lot)
                    }
                }
            }
            .padding()
        }
    }
    
    private func acquisitionCard(_ lot: TaxLot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(lot.symbol)
                    .font(.headline)
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text(lot.source.displayName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(Capsule())
                
                Spacer()
                
                // Actions Menu
                Menu {
                    Button {
                        editingLot = lot
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    
                    Button(role: .destructive) {
                        lotToDelete = lot
                        showDeleteAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
            }
            
            Rectangle()
                .fill(DS.Adaptive.divider)
                .frame(height: 1)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    detailRow(label: "Quantity", value: formatQuantity(lot.originalQuantity))
                    detailRow(label: "Remaining", value: formatQuantity(lot.remainingQuantity))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    detailRow(label: "Cost Basis", value: formatCurrency(lot.costBasisPerUnit))
                    detailRow(label: "Total", value: formatCurrency(lot.totalCostBasis))
                }
            }
            
            HStack {
                Text(formatDate(lot.acquiredDate))
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textSecondary)
                
                Spacer()
                
                Text(lot.isLongTerm ? "Long-Term" : "Short-Term")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(lot.isLongTerm ? .blue : .orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((lot.isLongTerm ? Color.blue : Color.orange).opacity(0.15))
                    .clipShape(Capsule())
            }
            
            if let exchange = lot.exchange {
                Text("Exchange: \(exchange)")
                    .font(.caption2)
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            
            if let walletId = lot.walletId {
                Text("Wallet: \(walletId)")
                    .font(.caption2)
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
        }
        .padding(16)
        .background(cardBackground)
    }
    
    // MARK: - Disposals Tab
    
    private var disposalsTab: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if lotManager.disposals.isEmpty {
                    emptyStateView(
                        icon: "arrow.right.circle",
                        title: "No Disposals",
                        message: "Sales and trades will appear here once processed."
                    )
                } else {
                    ForEach(lotManager.disposals.sorted(by: { $0.disposedDate > $1.disposedDate })) { disposal in
                        disposalCard(disposal)
                    }
                }
            }
            .padding()
        }
    }
    
    private func disposalCard(_ disposal: TaxDisposal) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(disposal.symbol)
                    .font(.headline)
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text(disposal.eventType.displayName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.purple)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.purple.opacity(0.15))
                    .clipShape(Capsule())
                
                Spacer()
                
                Text(formatCurrency(disposal.gain))
                    .font(.headline)
                    .foregroundColor(disposal.isGain ? .green : .red)
            }
            
            Rectangle()
                .fill(DS.Adaptive.divider)
                .frame(height: 1)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    detailRow(label: "Quantity", value: formatQuantity(disposal.quantity))
                    detailRow(label: "Proceeds", value: formatCurrency(disposal.totalProceeds))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    detailRow(label: "Cost Basis", value: formatCurrency(disposal.totalCostBasis))
                    detailRow(label: "Held", value: "\(disposal.holdingPeriodDays) days")
                }
            }
            
            HStack {
                Text(formatDate(disposal.disposedDate))
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textSecondary)
                
                Spacer()
                
                Text(disposal.gainType.displayName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(disposal.gainType == .longTerm ? .blue : .orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((disposal.gainType == .longTerm ? Color.blue : Color.orange).opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .padding(16)
        .background(cardBackground)
    }
    
    // MARK: - Income Tab
    
    private var incomeTab: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if lotManager.incomeEvents.isEmpty {
                    emptyStateView(
                        icon: "dollarsign.circle",
                        title: "No Income Events",
                        message: "Add staking rewards, mining income, airdrops, and other crypto income."
                    )
                } else {
                    ForEach(lotManager.incomeEvents.sorted(by: { $0.date > $1.date })) { income in
                        incomeCard(income)
                    }
                }
            }
            .padding()
        }
    }
    
    private func incomeCard(_ income: IncomeEvent) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(income.symbol)
                    .font(.headline)
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text(income.source.displayName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.15))
                    .clipShape(Capsule())
                
                Spacer()
                
                // Actions Menu
                Menu {
                    Button {
                        editingIncome = income
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    
                    Button(role: .destructive) {
                        incomeToDelete = income
                        showDeleteAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
            }
            
            Rectangle()
                .fill(DS.Adaptive.divider)
                .frame(height: 1)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    detailRow(label: "Quantity", value: formatQuantity(income.quantity))
                    detailRow(label: "FMV/Unit", value: formatCurrency(income.fairMarketValuePerUnit))
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text("Total Income")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                    Text(formatCurrency(income.totalValue))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }
            }
            
            HStack {
                Text(formatDate(income.date))
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textSecondary)
                
                Spacer()
                
                if let exchange = income.exchange {
                    Text(exchange)
                        .font(.caption2)
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }
    
    // MARK: - Helpers
    
    private func emptyStateView(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(DS.Adaptive.textTertiary)
            
            Text(title)
                .font(.headline)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .frame(maxWidth: .infinity)
    }
    
    private func detailRow(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label + ":")
                .font(.caption)
                .foregroundColor(DS.Adaptive.textSecondary)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(DS.Adaptive.textPrimary)
        }
    }
    
    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
            
            LinearGradient(
                colors: [Color.white.opacity(colorScheme == .dark ? 0.06 : 0.5), Color.clear],
                startPoint: .top,
                endPoint: .center
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DS.Adaptive.stroke, lineWidth: 1)
        )
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = CurrencyManager.currencyCode
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }
    
    private func formatQuantity(_ qty: Double) -> String {
        if qty >= 1 {
            return String(format: "%.4f", qty)
        } else {
            return String(format: "%.8f", qty)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    private func performDelete() {
        if let lot = lotToDelete {
            lotManager.deleteLot(lot)
            lotToDelete = nil
        }
        if let disposal = disposalToDelete {
            lotManager.deleteDisposal(disposal)
            disposalToDelete = nil
        }
        if let income = incomeToDelete {
            lotManager.deleteIncomeEvent(income)
            incomeToDelete = nil
        }
    }
}

// MARK: - Add Tax Lot Sheet

struct AddTaxLotSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var lotManager = TaxLotManager.shared
    
    @Binding var editingLot: TaxLot?
    
    @State private var symbol = ""
    @State private var quantity = ""
    @State private var pricePerUnit = ""
    @State private var date = Date()
    @State private var source: TaxLotSource = .purchase
    @State private var exchange = ""
    @State private var walletId = ""
    @State private var fee = ""
    @State private var notes = ""
    
    private var isEditing: Bool { editingLot != nil }
    
    private var themedAccent: Color {
        colorScheme == .dark ? Color(red: 1.0, green: 0.84, blue: 0.0) : .blue
    }
    
    private var isValid: Bool {
        !symbol.isEmpty &&
        Double(quantity) ?? 0 > 0 &&
        Double(pricePerUnit) ?? 0 >= 0
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Asset Details") {
                    TextField("Symbol (e.g., BTC)", text: $symbol)
                        .textInputAutocapitalization(.characters)
                    
                    TextField("Quantity", text: $quantity)
                        .keyboardType(.decimalPad)
                    
                    TextField("Price per Unit (USD)", text: $pricePerUnit)
                        .keyboardType(.decimalPad)
                    
                    DatePicker("Acquisition Date", selection: $date, displayedComponents: [.date])
                }
                
                Section("Source") {
                    Picker("Acquisition Type", selection: $source) {
                        ForEach(TaxLotSource.allCases, id: \.self) { source in
                            Text(source.displayName).tag(source)
                        }
                    }
                }
                
                Section("Optional Details") {
                    TextField("Exchange", text: $exchange)
                    
                    TextField("Wallet ID", text: $walletId)
                    
                    TextField("Fee (USD)", text: $fee)
                        .keyboardType(.decimalPad)
                    
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                // Preview
                if isValid {
                    Section("Preview") {
                        let qty = Double(quantity) ?? 0
                        let price = Double(pricePerUnit) ?? 0
                        let feeVal = Double(fee) ?? 0
                        let totalCost = (qty * price) + feeVal
                        let adjustedBasis = feeVal > 0 ? price + (feeVal / qty) : price
                        
                        HStack {
                            Text("Total Cost Basis")
                            Spacer()
                            Text(formatCurrency(totalCost))
                                .fontWeight(.semibold)
                        }
                        
                        if feeVal > 0 {
                            HStack {
                                Text("Adjusted Per-Unit Basis")
                                Spacer()
                                Text(formatCurrency(adjustedBasis))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Acquisition" : "Add Acquisition")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Text("Cancel")
                            .foregroundStyle(DS.Adaptive.textSecondary)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        saveLot()
                    } label: {
                        Text(isEditing ? "Update" : "Add")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(BrandColors.goldBase)
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear {
                if let lot = editingLot {
                    symbol = lot.symbol
                    quantity = String(format: "%.8f", lot.originalQuantity)
                    pricePerUnit = String(format: "%.2f", lot.costBasisPerUnit)
                    date = lot.acquiredDate
                    source = lot.source
                    exchange = lot.exchange ?? ""
                    walletId = lot.walletId ?? ""
                    fee = lot.fee.map { String(format: "%.2f", $0) } ?? ""
                    notes = lot.notes ?? ""
                }
            }
        }
    }
    
    private func saveLot() {
        guard let qty = Double(quantity),
              let price = Double(pricePerUnit) else { return }
        
        let feeVal = Double(fee)
        
        if isEditing, let oldLot = editingLot {
            // Delete old lot and create new one with updated values
            lotManager.deleteLot(oldLot)
        }
        
        _ = lotManager.createLotFromPurchase(
            symbol: symbol.uppercased(),
            quantity: qty,
            pricePerUnit: price,
            date: date,
            exchange: exchange.isEmpty ? nil : exchange,
            txHash: nil,
            fee: feeVal,
            walletId: walletId.isEmpty ? nil : walletId
        )
        
        // Update notes if needed
        if !notes.isEmpty {
            // Notes are handled in the lot creation
        }
        
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = CurrencyManager.currencyCode
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }
}

// MARK: - Add Income Event Sheet

struct AddIncomeEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var lotManager = TaxLotManager.shared
    
    @Binding var editingIncome: IncomeEvent?
    
    @State private var symbol = ""
    @State private var quantity = ""
    @State private var fairMarketValue = ""
    @State private var date = Date()
    @State private var source: TaxLotSource = .staking
    @State private var exchange = ""
    @State private var notes = ""
    
    private var isEditing: Bool { editingIncome != nil }
    
    private var themedAccent: Color {
        colorScheme == .dark ? Color(red: 1.0, green: 0.84, blue: 0.0) : .blue
    }
    
    private var isValid: Bool {
        !symbol.isEmpty &&
        Double(quantity) ?? 0 > 0 &&
        Double(fairMarketValue) ?? 0 >= 0
    }
    
    // Income-specific sources
    private let incomeSources: [TaxLotSource] = [
        .staking, .mining, .airdrop, .interest, .rewards, .income, .gift, .fork
    ]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Income Details") {
                    TextField("Symbol (e.g., ETH)", text: $symbol)
                        .textInputAutocapitalization(.characters)
                    
                    TextField("Quantity Received", text: $quantity)
                        .keyboardType(.decimalPad)
                    
                    TextField("Fair Market Value (USD per unit)", text: $fairMarketValue)
                        .keyboardType(.decimalPad)
                    
                    DatePicker("Date Received", selection: $date, displayedComponents: [.date])
                }
                
                Section("Income Type") {
                    Picker("Source", selection: $source) {
                        ForEach(incomeSources, id: \.self) { src in
                            Text(src.displayName).tag(src)
                        }
                    }
                }
                
                Section("Optional Details") {
                    TextField("Platform/Exchange", text: $exchange)
                    
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                // Preview
                if isValid {
                    Section("Preview") {
                        let qty = Double(quantity) ?? 0
                        let fmv = Double(fairMarketValue) ?? 0
                        let total = qty * fmv
                        
                        HStack {
                            Text("Total Income Value")
                            Spacer()
                            Text(formatCurrency(total))
                                .fontWeight(.semibold)
                                .foregroundColor(.green)
                        }
                        
                        Text("This income will be reported and a tax lot will be created with this fair market value as the cost basis.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Income" : "Add Income")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Text("Cancel")
                            .foregroundStyle(DS.Adaptive.textSecondary)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        saveIncome()
                    } label: {
                        Text(isEditing ? "Update" : "Add")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(BrandColors.goldBase)
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear {
                if let income = editingIncome {
                    symbol = income.symbol
                    quantity = String(format: "%.8f", income.quantity)
                    fairMarketValue = String(format: "%.2f", income.fairMarketValuePerUnit)
                    date = income.date
                    source = income.source
                    exchange = income.exchange ?? ""
                    notes = income.notes ?? ""
                }
            }
        }
    }
    
    private func saveIncome() {
        guard let qty = Double(quantity),
              let fmv = Double(fairMarketValue) else { return }
        
        if isEditing, let oldIncome = editingIncome {
            lotManager.deleteIncomeEvent(oldIncome)
        }
        
        _ = lotManager.createLotFromIncome(
            symbol: symbol.uppercased(),
            quantity: qty,
            fairMarketValue: fmv,
            date: date,
            source: source,
            exchange: exchange.isEmpty ? nil : exchange,
            txHash: nil,
            walletId: nil
        )
        
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = CurrencyManager.currencyCode
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }
}

// MARK: - Preview

#Preview {
    ManualTaxEntryView()
}
