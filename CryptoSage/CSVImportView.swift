//
//  CSVImportView.swift
//  CryptoSage
//
//  View for importing cryptocurrency transactions from CSV files.
//

import SwiftUI
import UniformTypeIdentifiers

struct CSVImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject var portfolioViewModel: PortfolioViewModel
    
    @State private var isImporting = false
    @State private var importResult: CSVImportResult?
    @State private var errorMessage: String?
    @State private var isProcessing = false
    @State private var showingFilePicker = false
    @State private var importSuccessful = false
    @State private var importedCount = 0
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        VStack(spacing: 0) {
            CSPageHeader(title: "Import from CSV", leadingAction: { dismiss() })
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Header
                    headerSection
                    
                    // Import Button
                    importButton
                    
                    // How It Works
                    howItWorksSection
                    
                    // Supported Formats
                    supportedFormatsSection
                    
                    // Results
                    if let result = importResult {
                        resultsSection(result)
                    }
                    
                    // Error
                    if let error = errorMessage {
                        errorSection(error)
                    }
                    
                    // Success Banner
                    if importSuccessful {
                        successBanner
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollViewBackSwipeFix()
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: CSVImportService.supportedTypes,
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
    }
    
    // MARK: - Sections
    
    private var headerSection: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(BrandColors.goldBase.opacity(0.12))
                    .frame(width: 68, height: 68)
                
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [BrandColors.goldLight, BrandColors.goldBase],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            
            Text("Import Transactions")
                .font(.title3.weight(.bold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Text("Add your transaction history from exchanges or portfolio trackers")
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .padding(.vertical, 8)
    }
    
    private var importButton: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showingFilePicker = true
        }) {
            HStack(spacing: 10) {
                if isProcessing {
                    ProgressView()
                        .tint(isDark ? .black : .white)
                } else {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(isProcessing ? "Processing..." : "Select CSV File")
                    .font(.subheadline.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundColor(isDark ? .black : .white)
            .background(
                LinearGradient(
                    colors: isDark
                        ? [BrandColors.goldLight, BrandColors.goldBase]
                        : [Color(red: 0.78, green: 0.62, blue: 0.14), Color(red: 0.66, green: 0.48, blue: 0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isDark ? Color.white.opacity(0.3) : Color.clear, lineWidth: 0.5)
            )
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .opacity(isProcessing ? 0.7 : 1)
    }
    
    private var howItWorksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How It Works")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            VStack(alignment: .leading, spacing: 10) {
                stepRow(number: "1", text: "Export your transactions as CSV from your exchange")
                stepRow(number: "2", text: "Tap \"Select CSV File\" and choose the file")
                stepRow(number: "3", text: "Review the detected transactions")
                stepRow(number: "4", text: "Confirm to add them to your portfolio")
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(DS.Adaptive.stroke, lineWidth: 1)
                )
        )
    }
    
    private func stepRow(number: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.black)
                .frame(width: 22, height: 22)
                .background(
                    Circle().fill(BrandColors.goldBase)
                )
            
            Text(text)
                .font(.caption)
                .foregroundColor(DS.Adaptive.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    
    private var supportedFormatsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Supported Formats")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            // Wrap formats in a flowing layout
            FlowLayout(spacing: 8) {
                ForEach(CSVFormat.allCases, id: \.rawValue) { format in
                    HStack(spacing: 5) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color.green)
                            .font(.system(size: 11))
                        Text(format.rawValue)
                            .font(.caption.weight(.medium))
                            .foregroundColor(DS.Adaptive.textPrimary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(DS.Adaptive.cardBackground)
                            .overlay(
                                Capsule()
                                    .stroke(DS.Adaptive.stroke, lineWidth: 1)
                            )
                    )
                }
            }
            
            Text("Don't see your exchange? Use the Generic format with columns: symbol, quantity, price, date, type.")
                .font(.caption)
                .foregroundColor(DS.Adaptive.textTertiary)
                .padding(.top, 2)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(DS.Adaptive.stroke, lineWidth: 1)
                )
        )
    }
    
    private func resultsSection(_ result: CSVImportResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("File Processed")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Spacer()
                
                if !result.transactions.isEmpty && !importSuccessful {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        importTransactions(result.transactions)
                    } label: {
                        Text("Import \(result.transactions.count)")
                            .font(.caption.weight(.bold))
                            .foregroundColor(isDark ? .black : .white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(
                                    LinearGradient(
                                        colors: isDark
                                            ? [BrandColors.goldLight, BrandColors.goldBase]
                                            : [Color(red: 0.78, green: 0.62, blue: 0.14), Color(red: 0.66, green: 0.48, blue: 0.06)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Rectangle()
                .fill(DS.Adaptive.stroke)
                .frame(height: 1)
            
            HStack {
                Text("Format:")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textTertiary)
                Spacer()
                Text(result.detectedFormat.rawValue)
                    .font(.caption.weight(.medium))
                    .foregroundColor(DS.Adaptive.textPrimary)
            }
            
            HStack {
                Text("Transactions:")
                    .font(.caption)
                    .foregroundColor(DS.Adaptive.textTertiary)
                Spacer()
                Text("\(result.successCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.green)
            }
            
            if result.failedCount > 0 {
                HStack {
                    Text("Skipped:")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                    Spacer()
                    Text("\(result.failedCount)")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.orange)
                }
            }
            
            if !result.transactions.isEmpty {
                Rectangle()
                    .fill(DS.Adaptive.stroke)
                    .frame(height: 1)
                
                Text("Preview")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textTertiary)
                
                ForEach(result.transactions.prefix(5)) { tx in
                    transactionPreviewRow(tx)
                }
                
                if result.transactions.count > 5 {
                    Text("+ \(result.transactions.count - 5) more")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    private func transactionPreviewRow(_ tx: Transaction) -> some View {
        HStack(spacing: 10) {
            Text(tx.isBuy ? "BUY" : "SELL")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(tx.isBuy ? .green : .red)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(tx.isBuy ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
                )
            
            Text(tx.coinSymbol)
                .font(.caption.weight(.semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 1) {
                Text(String(format: "%.6f", tx.quantity))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(DS.Adaptive.textPrimary)
                Text(String(format: "$%.2f", tx.pricePerUnit))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
        }
        .padding(.vertical, 3)
    }
    
    private func errorSection(_ error: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 16))
            Text(error)
                .font(.caption)
                .foregroundColor(DS.Adaptive.textPrimary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                )
        )
    }
    
    private var successBanner: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 56, height: 56)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.green)
            }
            
            Text("Import Successful")
                .font(.headline.weight(.semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Text("\(importedCount) transaction\(importedCount == 1 ? "" : "s") added to your portfolio")
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
                .multilineTextAlignment(.center)
            
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            }) {
                Text("Done")
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(isDark ? .black : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                LinearGradient(
                                    colors: isDark
                                        ? [BrandColors.goldLight, BrandColors.goldBase]
                                        : [Color(red: 0.78, green: 0.62, blue: 0.14), Color(red: 0.66, green: 0.48, blue: 0.06)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.green.opacity(0.3), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Actions
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importFile(url)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
    
    private func importFile(_ url: URL) {
        isProcessing = true
        errorMessage = nil
        importResult = nil
        
        Task {
            do {
                let result = try await CSVImportService.shared.importFromURL(url)
                await MainActor.run {
                    importResult = result
                    isProcessing = false
                    
                    if result.transactions.isEmpty && !result.errors.isEmpty {
                        errorMessage = "No valid transactions found. " + (result.errors.first ?? "")
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }
    
    private func importTransactions(_ transactions: [Transaction]) {
        for transaction in transactions {
            let manualTx = Transaction(
                coinSymbol: transaction.coinSymbol,
                quantity: transaction.quantity,
                pricePerUnit: transaction.pricePerUnit,
                date: transaction.date,
                isBuy: transaction.isBuy,
                isManual: true
            )
            portfolioViewModel.addTransaction(manualTx)
        }
        
        importedCount = transactions.count
        importSuccessful = true
        importResult = nil
    }
}

#if DEBUG
struct CSVImportView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            CSVImportView()
                .environmentObject(PortfolioViewModel.sample)
        }
    }
}
#endif
