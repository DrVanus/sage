//
//  TaxSettingsView.swift
//  CryptoSage
//
//  Settings view for tax reporting configuration.
//

import SwiftUI

// MARK: - Tax Settings View

struct TaxSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var taxEngine = TaxEngine.shared
    @StateObject private var lotManager = TaxLotManager.shared
    
    @State private var selectedMethod: AccountingMethod = .fifo
    @State private var filingStatus: FilingStatus = .single
    @State private var showClearDataAlert = false
    @State private var showImportSheet = false
    
    // Tax year settings
    @AppStorage("Tax.DefaultYear") private var defaultTaxYear = Calendar.current.component(.year, from: Date()) - 1
    @AppStorage("Tax.ShowWashSales") private var showWashSales = true
    @AppStorage("Tax.AutoImport") private var autoImportTransactions = false
    @AppStorage("Tax.PerWalletCostBasis") private var usePerWalletCostBasis = false // IRS 2025 requirement
    @AppStorage("Tax.Jurisdiction") private var jurisdictionRaw = TaxJurisdiction.us.rawValue
    
    private var jurisdiction: TaxJurisdiction {
        get { TaxJurisdiction(rawValue: jurisdictionRaw) ?? .us }
        set { jurisdictionRaw = newValue.rawValue }
    }
    
    /// Theme-consistent accent color (gold in dark mode, blue in light mode)
    private var themedAccent: Color {
        colorScheme == .dark ? Color(red: 1.0, green: 0.84, blue: 0.0) : .blue
    }
    
    var body: some View {
        VStack(spacing: 0) {
            CSPageHeader(title: "Tax Settings", leadingAction: { dismiss() }) {
                Button("Done") { dismiss() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(BrandColors.goldBase)
            }
            
            Form {
                // Accounting Method
                Section {
                    ForEach(AccountingMethod.allCases) { method in
                        Button {
                            selectedMethod = method
                            taxEngine.setAccountingMethod(method)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(method.displayName)
                                        .foregroundColor(.primary)
                                    Text(method.shortDescription)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if selectedMethod == method {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(themedAccent)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Cost Basis Method")
                } footer: {
                    Text("FIFO is the default and most commonly used. HIFO can minimize taxes but requires good record keeping. Once set, you should use the same method consistently.")
                }
                
                // Tax Jurisdiction
                Section {
                    Picker("Country/Jurisdiction", selection: $jurisdictionRaw) {
                        ForEach(TaxJurisdiction.allCases) { jur in
                            Text(jur.displayName).tag(jur.rawValue)
                        }
                    }
                } header: {
                    Text("Tax Jurisdiction")
                } footer: {
                    let jur = TaxJurisdiction(rawValue: jurisdictionRaw) ?? .us
                    let rates = JurisdictionTaxRates.rates(for: jur)
                    Text("\(jur.taxAgency) • \(rates.notes)")
                }
                
                // Filing Status (US only)
                if jurisdictionRaw == TaxJurisdiction.us.rawValue {
                    Section {
                        Picker("Filing Status", selection: $filingStatus) {
                            ForEach(FilingStatus.allCases, id: \.self) { status in
                                Text(status.displayName).tag(status)
                            }
                        }
                    } header: {
                        Text("Tax Estimation")
                    } footer: {
                        Text("Used for estimated tax calculations. Consult a tax professional for accurate advice.")
                    }
                }
                
                // Features
                Section {
                    Toggle("Show Wash Sale Warnings", isOn: $showWashSales)
                    
                    Toggle("Auto-Import Transactions", isOn: $autoImportTransactions)
                    
                    Toggle("Per-Wallet Cost Basis", isOn: $usePerWalletCostBasis)
                } header: {
                    Text("Features")
                } footer: {
                    Text("Wash sale detection alerts you when you might trigger the wash sale rule. Per-wallet cost basis tracking is required by the IRS starting in 2025 - each wallet/exchange tracks cost basis separately.")
                }
                
                // Wallet Summary (if per-wallet is enabled)
                if usePerWalletCostBasis {
                    Section {
                        let walletSummaries = lotManager.perWalletSummary()
                        if walletSummaries.isEmpty {
                            Text("No wallets with tax lots")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(walletSummaries) { summary in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(summary.displayName)
                                            .font(.subheadline)
                                        Text("\(summary.lotCount) lots • \(summary.symbols.prefix(3).joined(separator: ", "))\(summary.symbols.count > 3 ? "..." : "")")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text(formatCurrency(summary.totalCostBasis))
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                }
                            }
                        }
                    } header: {
                        Text("Cost Basis by Wallet")
                    } footer: {
                        Text("When selling crypto, the cost basis will be calculated from the same wallet/exchange where the sale occurs.")
                    }
                }
                
                // Tax Lots Summary
                Section {
                    HStack {
                        Text("Total Tax Lots")
                        Spacer()
                        Text("\(lotManager.lots.count)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Active Assets")
                        Spacer()
                        Text("\(lotManager.symbols.count)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Disposals Recorded")
                        Spacer()
                        Text("\(lotManager.disposals.count)")
                            .foregroundColor(.secondary)
                    }
                    
                    if lotManager.washSales.count > 0 {
                        HStack {
                            Text("Wash Sales Detected")
                            Spacer()
                            Text("\(lotManager.washSales.count)")
                                .foregroundColor(.orange)
                        }
                    }
                } header: {
                    Text("Tax Data Summary")
                }
                
                // Data Management
                Section {
                    Button {
                        showImportSheet = true
                    } label: {
                        Label("Import Transactions", systemImage: "square.and.arrow.down")
                    }
                    
                    NavigationLink {
                        ManualTaxEntryView()
                    } label: {
                        Label("Add/Edit Transactions", systemImage: "pencil.and.list.clipboard")
                    }
                    
                    NavigationLink {
                        TaxLotsListView()
                    } label: {
                        Label("View Tax Lots", systemImage: "list.bullet.rectangle")
                    }
                    
                    Button(role: .destructive) {
                        showClearDataAlert = true
                    } label: {
                        Label("Clear All Tax Data", systemImage: "trash")
                    }
                } header: {
                    Text("Data Management")
                }
                
                // Help
                Section {
                    NavigationLink {
                        TaxHelpView()
                    } label: {
                        Label("Tax Reporting Guide", systemImage: "questionmark.circle")
                    }
                    
                    Link(destination: URL(string: "https://www.irs.gov/forms-pubs/about-schedule-d-form-1040")!) {
                        HStack {
                            Label("IRS Schedule D Info", systemImage: "link")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                        }
                    }
                } header: {
                    Text("Help & Resources")
                }
            }
            .navigationBarHidden(true)
            .enableInteractivePopGesture()
            .edgeSwipeToDismiss(onDismiss: { dismiss() })
            .onAppear {
                selectedMethod = taxEngine.accountingMethod
            }
            .alert("Clear Tax Data", isPresented: $showClearDataAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    lotManager.clearAll()
                }
            } message: {
                Text("This will permanently delete all tax lots, disposals, and income events. This cannot be undone.")
            }
            .sheet(isPresented: $showImportSheet) {
                ImportTransactionsSheet()
            }
        }
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = CurrencyManager.currencyCode
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }
}

// MARK: - Tax Lots List View

struct TaxLotsListView: View {
    @StateObject private var lotManager = TaxLotManager.shared
    
    var body: some View {
        List {
            ForEach(lotManager.symbols, id: \.self) { symbol in
                Section(symbol) {
                    let lots = lotManager.availableLots(for: symbol)
                    ForEach(lots) { lot in
                        taxLotRow(lot)
                    }
                }
            }
        }
        .navigationTitle("Tax Lots")
        .overlay {
            if lotManager.lots.isEmpty {
                ContentUnavailableView(
                    "No Tax Lots",
                    systemImage: "doc.text",
                    description: Text("Import transactions to create tax lots.")
                )
            }
        }
    }
    
    private func taxLotRow(_ lot: TaxLot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(format: "%.6f %@", lot.remainingQuantity, lot.symbol))
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text(lot.isLongTerm ? "Long-Term" : "Short-Term")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(lot.isLongTerm ? Color.blue.opacity(0.2) : Color.orange.opacity(0.2))
                    .cornerRadius(4)
            }
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cost Basis")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatCurrency(lot.costBasisPerUnit))
                        .font(.caption)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Acquired")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(formatDate(lot.acquiredDate))
                        .font(.caption)
                }
            }
            
            HStack {
                Text(lot.source.displayName)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("\(lot.ageInDays) days old")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = CurrencyManager.currencyCode
        return formatter.string(from: NSNumber(value: amount)) ?? "$0.00"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Import Transactions Sheet

struct ImportTransactionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var portfolioVM: PortfolioViewModel
    @StateObject private var lotManager = TaxLotManager.shared
    
    @State private var isImporting = false
    @State private var importCount = 0
    @State private var showCSVImport = false
    
    /// Theme-consistent accent color
    private var themedAccent: Color {
        colorScheme == .dark ? Color(red: 1.0, green: 0.84, blue: 0.0) : .blue
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 64))
                    .foregroundStyle(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange]
                                : [.blue, .blue.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("Import Transactions")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Import transactions from your portfolio or from exchange CSV files.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                VStack(spacing: 12) {
                    HStack {
                        Text("Portfolio Transactions")
                        Spacer()
                        Text("\(portfolioVM.transactions.count)")
                            .fontWeight(.medium)
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    
                    HStack {
                        Text("Existing Tax Lots")
                        Spacer()
                        Text("\(lotManager.lots.count)")
                            .fontWeight(.medium)
                    }
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                }
                .padding(.horizontal)
                
                Spacer()
                
                if importCount > 0 {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Imported \(importCount) transactions")
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                }
                
                VStack(spacing: 12) {
                    // Import from Portfolio button
                    Button {
                        importTransactions()
                    } label: {
                        HStack {
                            if isImporting {
                                ProgressView()
                                    .tint(colorScheme == .dark ? .black : .white)
                            } else {
                                Image(systemName: "folder.badge.plus")
                                Text("Import from Portfolio")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundColor(colorScheme == .dark ? .black : .white)
                        .background(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange]
                                    : [.blue, .blue.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .disabled(isImporting || portfolioVM.transactions.isEmpty)
                    .opacity(isImporting || portfolioVM.transactions.isEmpty ? 0.6 : 1.0)
                    
                    // Import CSV button
                    Button {
                        showCSVImport = true
                    } label: {
                        HStack {
                            Image(systemName: "doc.text")
                            Text("Import CSV File")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundColor(themedAccent)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(themedAccent, lineWidth: 2)
                        )
                    }
                }
                .padding(.horizontal)
                
                Button("Cancel") { dismiss() }
                    .foregroundColor(themedAccent)
                    .padding(.bottom)
            }
            .padding(.top, 40)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showCSVImport) {
                CSVImportSheet()
            }
        }
    }
    
    private func importTransactions() {
        isImporting = true
        let transactions = portfolioVM.transactions
        DispatchQueue.global(qos: .userInitiated).async {
            lotManager.importFromTransactions(transactions)
            DispatchQueue.main.async {
                importCount = transactions.count
                isImporting = false
            }
        }
    }
}

// MARK: - CSV Import Sheet

struct CSVImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var lotManager = TaxLotManager.shared
    
    @State private var selectedFormat: ExchangeCSVFormat = .coinbase
    @State private var showFilePicker = false
    @State private var isImporting = false
    @State private var importResult: TaxCSVImportResult?
    @State private var importStats: (lots: Int, disposals: Int, income: Int)?
    @State private var errorMessage: String?
    
    private var themedAccent: Color {
        colorScheme == .dark ? Color(red: 1.0, green: 0.84, blue: 0.0) : .blue
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                FuturisticBackground()
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 12) {
                            Image(systemName: "doc.text.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: colorScheme == .dark
                                            ? [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange]
                                            : [.blue, .blue.opacity(0.8)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                            
                            Text("Import CSV")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(DS.Adaptive.textPrimary)
                            
                            Text("Import transaction history from your exchange")
                                .font(.subheadline)
                                .foregroundColor(DS.Adaptive.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 20)
                        
                        // Format Selection
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Exchange Format")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(DS.Adaptive.textSecondary)
                                .textCase(.uppercase)
                                .tracking(0.5)
                                .padding(.horizontal, 4)
                            
                            VStack(spacing: 0) {
                                ForEach(Array(ExchangeCSVFormat.allCases.enumerated()), id: \.element.id) { index, format in
                                    Button {
                                        UISelectionFeedbackGenerator().selectionChanged()
                                        selectedFormat = format
                                    } label: {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(format.displayName)
                                                    .font(.subheadline)
                                                    .foregroundColor(DS.Adaptive.textPrimary)
                                                Text(format.description)
                                                    .font(.caption)
                                                    .foregroundColor(DS.Adaptive.textSecondary)
                                            }
                                            
                                            Spacer()
                                            
                                            if selectedFormat == format {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(
                                                        LinearGradient(
                                                            colors: colorScheme == .dark
                                                                ? [Color(red: 1.0, green: 0.84, blue: 0.0), Color.orange]
                                                                : [.blue, .blue.opacity(0.8)],
                                                            startPoint: .topLeading,
                                                            endPoint: .bottomTrailing
                                                        )
                                                    )
                                            }
                                        }
                                        .padding(14)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    
                                    if index < ExchangeCSVFormat.allCases.count - 1 {
                                        Rectangle()
                                            .fill(DS.Adaptive.divider)
                                            .frame(height: 1)
                                    }
                                }
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(DS.Adaptive.cardBackground)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(DS.Adaptive.stroke, lineWidth: 1)
                            )
                        }
                        
                        // Import Result
                        if let result = importResult {
                            VStack(spacing: 12) {
                                // Success Stats
                                if result.successCount > 0 {
                                    VStack(spacing: 8) {
                                        HStack {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.green)
                                            Text("Successfully parsed \(result.successCount) transactions")
                                                .font(.subheadline)
                                                .foregroundColor(DS.Adaptive.textPrimary)
                                            Spacer()
                                        }
                                        
                                        if let stats = importStats {
                                            HStack {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text("Tax Lots: \(stats.lots)")
                                                        .font(.caption)
                                                    Text("Disposals: \(stats.disposals)")
                                                        .font(.caption)
                                                    Text("Income Events: \(stats.income)")
                                                        .font(.caption)
                                                }
                                                .foregroundColor(DS.Adaptive.textSecondary)
                                                Spacer()
                                            }
                                        }
                                    }
                                    .padding(14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color.green.opacity(0.1))
                                    )
                                }
                                
                                // Errors
                                if result.hasErrors {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Image(systemName: "exclamationmark.triangle.fill")
                                                .foregroundColor(.orange)
                                            Text("\(result.errorCount) rows had errors")
                                                .font(.subheadline)
                                                .foregroundColor(DS.Adaptive.textPrimary)
                                            Spacer()
                                        }
                                        
                                        ForEach(result.errors.prefix(3)) { error in
                                            Text("Row \(error.row): \(error.message)")
                                                .font(.caption)
                                                .foregroundColor(DS.Adaptive.textSecondary)
                                        }
                                        
                                        if result.errorCount > 3 {
                                            Text("... and \(result.errorCount - 3) more errors")
                                                .font(.caption)
                                                .foregroundColor(DS.Adaptive.textTertiary)
                                        }
                                    }
                                    .padding(14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color.orange.opacity(0.1))
                                    )
                                }
                            }
                        }
                        
                        // Error Message
                        if let error = errorMessage {
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                Text(error)
                                    .font(.subheadline)
                                    .foregroundColor(DS.Adaptive.textPrimary)
                                Spacer()
                            }
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.red.opacity(0.1))
                            )
                        }
                        
                        Spacer(minLength: 20)
                        
                        // Select File Button
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            showFilePicker = true
                        } label: {
                            HStack {
                                if isImporting {
                                    ProgressView()
                                        .tint(colorScheme == .dark ? .black : .white)
                                        .padding(.trailing, 8)
                                }
                                Image(systemName: "folder.badge.plus")
                                Text(isImporting ? "Importing..." : "Select CSV File")
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(colorScheme == .dark ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
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
                        .disabled(isImporting)
                        
                        // Done button (if we have results)
                        if importResult?.successCount ?? 0 > 0 {
                            Button("Done") {
                                dismiss()
                            }
                            .font(.headline)
                            .foregroundColor(themedAccent)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Import CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Text("Cancel")
                            .foregroundStyle(DS.Adaptive.textSecondary)
                    }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.commaSeparatedText, .text, .plainText],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
        }
    }
    
    private func handleFileImport(_ result: Result<[URL], Error>) {
        errorMessage = nil
        importResult = nil
        importStats = nil
        
        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                errorMessage = "No file selected"
                return
            }
            
            isImporting = true
            
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    // Start accessing security-scoped resource
                    guard url.startAccessingSecurityScopedResource() else {
                        DispatchQueue.main.async {
                            errorMessage = "Unable to access file"
                            isImporting = false
                        }
                        return
                    }
                    
                    defer { url.stopAccessingSecurityScopedResource() }
                    
                    let data = try Data(contentsOf: url)
                    let importService = TaxCSVImportService.shared
                    
                    // Try to auto-detect format first
                    let detectedFormat = importService.detectFormat(from: data) ?? selectedFormat
                    
                    let csvResult = importService.importCSV(data: data, format: detectedFormat)
                    
                    // Import into tax lots
                    let stats = lotManager.importFromCSV(csvResult)
                    
                    DispatchQueue.main.async {
                        importResult = csvResult
                        importStats = stats
                        isImporting = false
                        
                        if csvResult.successCount > 0 {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        } else if csvResult.hasErrors {
                            UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        errorMessage = "Failed to read file: \(error.localizedDescription)"
                        isImporting = false
                        UINotificationFeedbackGenerator().notificationOccurred(.error)
                    }
                }
            }
            
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Tax Help View

struct TaxHelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                helpSection(
                    title: "Understanding Cost Basis",
                    content: "Cost basis is what you originally paid for your crypto. When you sell, your gain or loss is calculated as: Proceeds - Cost Basis = Gain/Loss"
                )
                
                helpSection(
                    title: "FIFO vs HIFO",
                    content: "FIFO (First In, First Out) sells your oldest coins first. HIFO (Highest In, First Out) sells your highest cost basis coins first, which typically minimizes taxes on gains."
                )
                
                helpSection(
                    title: "Short-Term vs Long-Term",
                    content: "Assets held for less than 1 year are short-term and taxed as ordinary income (higher rates). Assets held for 1+ years are long-term and qualify for lower capital gains rates."
                )
                
                helpSection(
                    title: "Wash Sales",
                    content: "If you sell at a loss and buy back the same asset within 30 days (before or after), the loss may be disallowed under the wash sale rule. The IRS is expected to apply this rule to crypto."
                )
                
                helpSection(
                    title: "Taxable Events",
                    content: "The following are typically taxable events:\n• Selling crypto for fiat\n• Trading crypto for crypto\n• Using crypto to buy goods/services\n• Receiving crypto as income, mining, or staking rewards"
                )
                
                helpSection(
                    title: "Form 8949",
                    content: "Capital gains and losses from crypto are reported on IRS Form 8949 and summarized on Schedule D. You can export your data in Form 8949 format from the Tax Report."
                )
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Disclaimer")
                        .font(.headline)
                    
                    Text("This app provides tools for tracking crypto taxes but is not tax advice. Tax laws vary by jurisdiction and are subject to change. Always consult a qualified tax professional for your specific situation.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.yellow.opacity(0.1))
                .cornerRadius(12)
            }
            .padding()
        }
        .navigationTitle("Tax Guide")
    }
    
    private func helpSection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            
            Text(content)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - Preview

#Preview {
    TaxSettingsView()
        .environmentObject(PortfolioViewModel.sample)
}
