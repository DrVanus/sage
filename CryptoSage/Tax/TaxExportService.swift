//
//  TaxExportService.swift
//  CryptoSage
//
//  Export tax data to various formats for tax software.
//

import Foundation

// MARK: - Export Format

/// Supported export formats
public enum TaxExportFormat: String, CaseIterable, Identifiable {
    case form8949CSV = "form8949"
    case koinly = "koinly"
    case coinTracker = "cointracker"
    case taxBit = "taxbit"
    case turboTax = "turbotax"
    case genericCSV = "generic"
    case json = "json"
    // International formats
    case hmrcUK = "hmrc_uk"
    case craCanada = "cra_ca"
    case atoAustralia = "ato_au"
    case bzstGermany = "bzst_de"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .form8949CSV: return "IRS Form 8949 (CSV)"
        case .koinly: return "Koinly Universal Format"
        case .coinTracker: return "CoinTracker"
        case .taxBit: return "TaxBit"
        case .turboTax: return "TurboTax"
        case .genericCSV: return "Generic CSV"
        case .json: return "JSON (Full Data)"
        case .hmrcUK: return "HMRC Capital Gains (UK)"
        case .craCanada: return "CRA Schedule 3 (Canada)"
        case .atoAustralia: return "ATO CGT Report (Australia)"
        case .bzstGermany: return "BZSt Crypto (Germany)"
        }
    }
    
    public var fileExtension: String {
        switch self {
        case .json: return "json"
        default: return "csv"
        }
    }
    
    public var description: String {
        switch self {
        case .form8949CSV: return "Ready for IRS Schedule D"
        case .koinly: return "Import directly to Koinly"
        case .coinTracker: return "Import to CoinTracker"
        case .taxBit: return "Import to TaxBit"
        case .turboTax: return "Import to TurboTax"
        case .genericCSV: return "Standard CSV format"
        case .json: return "Complete data export"
        case .hmrcUK: return "For UK Self Assessment"
        case .craCanada: return "For Canadian tax filing"
        case .atoAustralia: return "For Australian tax return"
        case .bzstGermany: return "For German Anlage SO"
        }
    }
    
    /// SF Symbol icon name for visual identification
    public var iconName: String {
        switch self {
        case .form8949CSV: return "doc.text.fill"
        case .koinly: return "arrow.up.doc.fill"
        case .coinTracker: return "chart.bar.doc.horizontal.fill"
        case .taxBit: return "bitcoinsign.circle.fill"
        case .turboTax: return "arrow.right.doc.on.clipboard"
        case .genericCSV: return "tablecells.fill"
        case .json: return "curlybraces"
        case .hmrcUK: return "building.columns.fill"
        case .craCanada: return "leaf.fill"
        case .atoAustralia: return "globe.asia.australia.fill"
        case .bzstGermany: return "eurosign.circle.fill"
        }
    }
    
    public var isInternational: Bool {
        switch self {
        case .hmrcUK, .craCanada, .atoAustralia, .bzstGermany:
            return true
        default:
            return false
        }
    }
}

// MARK: - Tax Export Service

/// Service for exporting tax data
public final class TaxExportService {
    
    public static let shared = TaxExportService()
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd/yyyy"
        return formatter
    }()
    
    private let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    private let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
    
    private init() {}
    
    // MARK: - Public API
    
    /// Export tax report to specified format
    public func export(
        report: TaxReport,
        format: TaxExportFormat
    ) -> ExportResult {
        switch format {
        case .form8949CSV:
            return exportForm8949(report)
        case .koinly:
            return exportKoinly(report)
        case .coinTracker:
            return exportCoinTracker(report)
        case .taxBit:
            return exportTaxBit(report)
        case .turboTax:
            return exportTurboTax(report)
        case .genericCSV:
            return exportGenericCSV(report)
        case .json:
            return exportJSON(report)
        case .hmrcUK:
            return InternationalTaxExportService.shared.export(report: report, format: .hmrcCapitalGains)
        case .craCanada:
            return InternationalTaxExportService.shared.export(report: report, format: .craSchedule3)
        case .atoAustralia:
            return InternationalTaxExportService.shared.export(report: report, format: .atoCapitalGains)
        case .bzstGermany:
            return InternationalTaxExportService.shared.export(report: report, format: .bzstCrypto)
        }
    }
    
    /// Export disposals only (for partial exports)
    public func exportDisposals(
        _ disposals: [TaxDisposal],
        format: TaxExportFormat
    ) -> ExportResult {
        // Create a minimal report
        let report = TaxReport(
            taxYear: TaxYear.current,
            accountingMethod: .fifo,
            shortTermGain: disposals.filter { $0.gainType == .shortTerm }.reduce(0) { $0 + $1.gain },
            longTermGain: disposals.filter { $0.gainType == .longTerm }.reduce(0) { $0 + $1.gain },
            totalIncome: 0,
            washSaleAdjustment: 0,
            disposals: disposals,
            incomeEvents: [],
            washSales: [],
            form8949Rows: disposals.map { Form8949Row.from(disposal: $0) },
            generatedAt: Date()
        )
        return export(report: report, format: format)
    }
    
    // MARK: - Form 8949 Export
    
    private func exportForm8949(_ report: TaxReport) -> ExportResult {
        var csv = "Part,Description of Property,Date Acquired,Date Sold or Disposed,Proceeds,Cost or Other Basis,Adjustment Code,Adjustment Amount,Gain or Loss\n"
        
        for row in report.form8949Rows {
            let part = row.isShortTerm ? "I (Short-Term)" : "II (Long-Term)"
            let adjCode = row.adjustmentCode ?? ""
            let adjAmount = row.adjustmentAmount.map { formatCurrency($0) } ?? ""
            
            let line = [
                part,
                escapeCSV(row.description),
                dateFormatter.string(from: row.dateAcquired),
                dateFormatter.string(from: row.dateSold),
                formatCurrency(row.proceeds),
                formatCurrency(row.costBasis),
                adjCode,
                adjAmount,
                formatCurrency(row.gainOrLoss)
            ].joined(separator: ",")
            
            csv += line + "\n"
        }
        
        // Add summary rows
        let shortTermRows = report.form8949Rows.filter { $0.isShortTerm }
        let longTermRows = report.form8949Rows.filter { !$0.isShortTerm }
        
        csv += "\n"
        csv += "SUMMARY\n"
        csv += "Short-Term Transactions,\(shortTermRows.count)\n"
        csv += "Short-Term Proceeds,\(formatCurrency(shortTermRows.reduce(0) { $0 + $1.proceeds }))\n"
        csv += "Short-Term Cost Basis,\(formatCurrency(shortTermRows.reduce(0) { $0 + $1.costBasis }))\n"
        csv += "Short-Term Gain/Loss,\(formatCurrency(report.shortTermGain))\n"
        csv += "\n"
        csv += "Long-Term Transactions,\(longTermRows.count)\n"
        csv += "Long-Term Proceeds,\(formatCurrency(longTermRows.reduce(0) { $0 + $1.proceeds }))\n"
        csv += "Long-Term Cost Basis,\(formatCurrency(longTermRows.reduce(0) { $0 + $1.costBasis }))\n"
        csv += "Long-Term Gain/Loss,\(formatCurrency(report.longTermGain))\n"
        
        return ExportResult(
            data: csv,
            filename: "Form8949_\(report.taxYear.year).csv",
            format: .form8949CSV
        )
    }
    
    // MARK: - Koinly Export
    
    private func exportKoinly(_ report: TaxReport) -> ExportResult {
        // Koinly Universal Format
        var csv = "Date,Sent Amount,Sent Currency,Received Amount,Received Currency,Fee Amount,Fee Currency,Net Worth Amount,Net Worth Currency,Label,Description,TxHash\n"
        
        for disposal in report.disposals {
            // Koinly format: sales are "Sent" transactions
            let line = [
                timestampFormatter.string(from: disposal.disposedDate),
                String(format: "%.8f", disposal.quantity),       // Sent Amount
                disposal.symbol,                                  // Sent Currency
                String(format: "%.2f", disposal.totalProceeds),  // Received Amount (USD)
                "USD",                                            // Received Currency
                "",                                               // Fee Amount
                "",                                               // Fee Currency
                String(format: "%.2f", disposal.totalProceeds),  // Net Worth Amount
                "USD",                                            // Net Worth Currency
                "sell",                                           // Label
                "Sale of \(disposal.symbol)",                     // Description
                disposal.txHash ?? ""                             // TxHash
            ].joined(separator: ",")
            
            csv += line + "\n"
        }
        
        // Add income events
        for income in report.incomeEvents {
            let label = koinlyLabelForSource(income.source)
            let line = [
                timestampFormatter.string(from: income.date),
                "",                                               // Sent Amount
                "",                                               // Sent Currency
                String(format: "%.8f", income.quantity),          // Received Amount
                income.symbol,                                    // Received Currency
                "",                                               // Fee Amount
                "",                                               // Fee Currency
                String(format: "%.2f", income.totalValue),        // Net Worth Amount
                "USD",                                            // Net Worth Currency
                label,                                            // Label
                "\(income.source.displayName) - \(income.symbol)", // Description
                income.txHash ?? ""                               // TxHash
            ].joined(separator: ",")
            
            csv += line + "\n"
        }
        
        return ExportResult(
            data: csv,
            filename: "Koinly_\(report.taxYear.year).csv",
            format: .koinly
        )
    }
    
    private func koinlyLabelForSource(_ source: TaxLotSource) -> String {
        switch source {
        case .mining: return "mining"
        case .staking: return "staking"
        case .airdrop: return "airdrop"
        case .fork: return "fork"
        case .gift: return "gift"
        case .income: return "income"
        case .interest: return "lending_interest"
        case .rewards: return "reward"
        default: return ""
        }
    }
    
    // MARK: - CoinTracker Export
    
    private func exportCoinTracker(_ report: TaxReport) -> ExportResult {
        // CoinTracker format
        var csv = "Date,Type,Base Currency,Base Amount,Quote Currency,Quote Amount,Fee Currency,Fee Amount,From,To,Blockchain,ID,Description\n"
        
        for disposal in report.disposals {
            let line = [
                timestampFormatter.string(from: disposal.disposedDate),
                "sell",
                disposal.symbol,
                String(format: "%.8f", disposal.quantity),
                "USD",
                String(format: "%.2f", disposal.totalProceeds),
                "",  // Fee Currency
                "",  // Fee Amount
                "",  // From
                "",  // To
                "",  // Blockchain
                disposal.txHash ?? "",
                ""   // Description
            ].joined(separator: ",")
            
            csv += line + "\n"
        }
        
        for income in report.incomeEvents {
            let line = [
                timestampFormatter.string(from: income.date),
                coinTrackerTypeForSource(income.source),
                "USD",
                String(format: "%.2f", income.totalValue),
                income.symbol,
                String(format: "%.8f", income.quantity),
                "",  // Fee Currency
                "",  // Fee Amount
                "",  // From
                "",  // To
                "",  // Blockchain
                income.txHash ?? "",
                income.source.displayName
            ].joined(separator: ",")
            
            csv += line + "\n"
        }
        
        return ExportResult(
            data: csv,
            filename: "CoinTracker_\(report.taxYear.year).csv",
            format: .coinTracker
        )
    }
    
    private func coinTrackerTypeForSource(_ source: TaxLotSource) -> String {
        switch source {
        case .mining: return "mining"
        case .staking: return "staking"
        case .airdrop: return "airdrop"
        case .fork: return "fork"
        case .gift: return "gift"
        case .income: return "income"
        case .interest: return "interest"
        case .rewards: return "reward"
        default: return "receive"
        }
    }
    
    // MARK: - TaxBit Export
    
    private func exportTaxBit(_ report: TaxReport) -> ExportResult {
        var csv = "Date and Time,Transaction Type,Sent Quantity,Sent Currency,Sending Source,Received Quantity,Received Currency,Receiving Destination,Fee,Fee Currency,Exchange Transaction ID,Blockchain Transaction Hash\n"
        
        for disposal in report.disposals {
            let line = [
                timestampFormatter.string(from: disposal.disposedDate),
                "Sale",
                String(format: "%.8f", disposal.quantity),
                disposal.symbol,
                disposal.exchange ?? "",
                String(format: "%.2f", disposal.totalProceeds),
                "USD",
                "",
                "",
                "",
                "",
                disposal.txHash ?? ""
            ].joined(separator: ",")
            
            csv += line + "\n"
        }
        
        return ExportResult(
            data: csv,
            filename: "TaxBit_\(report.taxYear.year).csv",
            format: .taxBit
        )
    }
    
    // MARK: - TurboTax Export
    
    private func exportTurboTax(_ report: TaxReport) -> ExportResult {
        // TurboTax CSV format (similar to Form 8949)
        var csv = "Currency Name,Purchase Date,Cost Basis,Date Sold,Proceeds\n"
        
        for disposal in report.disposals {
            let line = [
                "\(disposal.quantity) \(disposal.symbol)",
                dateFormatter.string(from: disposal.acquiredDate),
                formatCurrency(disposal.totalCostBasis),
                dateFormatter.string(from: disposal.disposedDate),
                formatCurrency(disposal.totalProceeds)
            ].joined(separator: ",")
            
            csv += line + "\n"
        }
        
        return ExportResult(
            data: csv,
            filename: "TurboTax_\(report.taxYear.year).csv",
            format: .turboTax
        )
    }
    
    // MARK: - Generic CSV Export
    
    private func exportGenericCSV(_ report: TaxReport) -> ExportResult {
        var csv = "Type,Symbol,Quantity,Acquired Date,Disposed Date,Cost Basis (USD),Proceeds (USD),Gain/Loss (USD),Holding Period,Exchange,Tx Hash\n"
        
        for disposal in report.disposals {
            let line = [
                disposal.eventType.displayName,
                disposal.symbol,
                String(format: "%.8f", disposal.quantity),
                isoDateFormatter.string(from: disposal.acquiredDate),
                isoDateFormatter.string(from: disposal.disposedDate),
                formatCurrency(disposal.totalCostBasis),
                formatCurrency(disposal.totalProceeds),
                formatCurrency(disposal.gain),
                disposal.gainType.displayName,
                disposal.exchange ?? "",
                disposal.txHash ?? ""
            ].joined(separator: ",")
            
            csv += line + "\n"
        }
        
        // Add income section
        if !report.incomeEvents.isEmpty {
            csv += "\n\nINCOME EVENTS\n"
            csv += "Type,Symbol,Quantity,Date,Fair Market Value (USD),Total Value (USD),Exchange,Tx Hash\n"
            
            for income in report.incomeEvents {
                let line = [
                    income.source.displayName,
                    income.symbol,
                    String(format: "%.8f", income.quantity),
                    isoDateFormatter.string(from: income.date),
                    formatCurrency(income.fairMarketValuePerUnit),
                    formatCurrency(income.totalValue),
                    income.exchange ?? "",
                    income.txHash ?? ""
                ].joined(separator: ",")
                
                csv += line + "\n"
            }
        }
        
        return ExportResult(
            data: csv,
            filename: "CryptoTax_\(report.taxYear.year).csv",
            format: .genericCSV
        )
    }
    
    // MARK: - JSON Export
    
    private func exportJSON(_ report: TaxReport) -> ExportResult {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        do {
            let data = try encoder.encode(report)
            let jsonString = String(data: data, encoding: .utf8) ?? "{}"
            
            return ExportResult(
                data: jsonString,
                filename: "TaxReport_\(report.taxYear.year).json",
                format: .json
            )
        } catch {
            return ExportResult(
                data: "{}",
                filename: "TaxReport_\(report.taxYear.year).json",
                format: .json,
                error: error
            )
        }
    }
    
    // MARK: - Helpers
    
    private func formatCurrency(_ amount: Double) -> String {
        String(format: "%.2f", amount)
    }
    
    private func escapeCSV(_ string: String) -> String {
        if string.contains(",") || string.contains("\"") || string.contains("\n") {
            return "\"\(string.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return string
    }
}

// MARK: - Export Result

/// Result of an export operation
public struct ExportResult {
    public let data: String
    public let filename: String
    public let format: TaxExportFormat
    public let error: Error?
    
    public var isSuccess: Bool { error == nil }
    
    public init(
        data: String,
        filename: String,
        format: TaxExportFormat,
        error: Error? = nil
    ) {
        self.data = data
        self.filename = filename
        self.format = format
        self.error = error
    }
    
    /// Save to documents directory
    public func saveToDocuments() -> URL? {
        guard let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        
        let fileURL = documentsURL.appendingPathComponent(filename)
        
        do {
            try data.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            #if DEBUG
            print("❌ Failed to save export: \(error)")
            #endif
            return nil
        }
    }
}
