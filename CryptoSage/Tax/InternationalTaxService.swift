//
//  InternationalTaxService.swift
//  CryptoSage
//
//  International tax support for UK, Canada, Australia, Germany, and other jurisdictions.
//

import Foundation

// MARK: - Tax Jurisdiction

/// Supported tax jurisdictions
public enum TaxJurisdiction: String, Codable, CaseIterable, Identifiable {
    case us = "US"
    case uk = "UK"
    case canada = "CA"
    case australia = "AU"
    case germany = "DE"
    case france = "FR"
    case netherlands = "NL"
    case spain = "ES"
    case portugal = "PT"
    case japan = "JP"
    case singapore = "SG"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .us: return "United States"
        case .uk: return "United Kingdom"
        case .canada: return "Canada"
        case .australia: return "Australia"
        case .germany: return "Germany"
        case .france: return "France"
        case .netherlands: return "Netherlands"
        case .spain: return "Spain"
        case .portugal: return "Portugal"
        case .japan: return "Japan"
        case .singapore: return "Singapore"
        }
    }
    
    public var currencyCode: String {
        switch self {
        case .us: return "USD"
        case .uk: return "GBP"
        case .canada: return "CAD"
        case .australia: return "AUD"
        case .germany, .france, .netherlands, .spain, .portugal: return "EUR"
        case .japan: return "JPY"
        case .singapore: return "SGD"
        }
    }
    
    public var taxAgency: String {
        switch self {
        case .us: return "IRS"
        case .uk: return "HMRC"
        case .canada: return "CRA"
        case .australia: return "ATO"
        case .germany: return "BZSt"
        case .france: return "DGFiP"
        case .netherlands: return "Belastingdienst"
        case .spain: return "AEAT"
        case .portugal: return "AT"
        case .japan: return "NTA"
        case .singapore: return "IRAS"
        }
    }
    
    public var longTermHoldingPeriod: Int {
        switch self {
        case .us, .uk, .canada, .australia: return 365
        case .germany: return 365 // Tax-free after 1 year if not staking
        case .portugal: return 365 // Crypto is tax-free for individuals (as of 2024)
        default: return 365
        }
    }
    
    /// Whether crypto-to-crypto trades are taxable
    public var cryptoToCryptoTaxable: Bool {
        switch self {
        case .portugal: return false // As of 2024
        case .germany: return true // But tax-free after 1 year
        default: return true
        }
    }
}

// MARK: - International Tax Rates

/// Tax rates for different jurisdictions
public struct JurisdictionTaxRates {
    public let jurisdiction: TaxJurisdiction
    public let shortTermRate: Double
    public let longTermRate: Double
    public let cryptoIncomeRate: Double
    public let wealthTaxRate: Double?
    public let notes: String
    
    public static func rates(for jurisdiction: TaxJurisdiction) -> JurisdictionTaxRates {
        switch jurisdiction {
        case .us:
            return JurisdictionTaxRates(
                jurisdiction: jurisdiction,
                shortTermRate: 0.37, // Max bracket
                longTermRate: 0.20, // Max LTCG
                cryptoIncomeRate: 0.37,
                wealthTaxRate: nil,
                notes: "Short-term taxed as ordinary income. LTCG rates: 0%, 15%, or 20%."
            )
            
        case .uk:
            return JurisdictionTaxRates(
                jurisdiction: jurisdiction,
                shortTermRate: 0.24, // 10% or 24% for higher rate
                longTermRate: 0.24,
                cryptoIncomeRate: 0.45, // Income tax rate
                wealthTaxRate: nil,
                notes: "Capital gains tax: 10% (basic rate) or 24% (higher rate). £3,000 annual exemption."
            )
            
        case .canada:
            return JurisdictionTaxRates(
                jurisdiction: jurisdiction,
                shortTermRate: 0.267, // 50% inclusion at ~53% top marginal
                longTermRate: 0.267,
                cryptoIncomeRate: 0.53,
                wealthTaxRate: nil,
                notes: "50% of capital gains are taxable at your marginal rate."
            )
            
        case .australia:
            return JurisdictionTaxRates(
                jurisdiction: jurisdiction,
                shortTermRate: 0.45, // Top marginal rate
                longTermRate: 0.225, // 50% discount after 1 year
                cryptoIncomeRate: 0.45,
                wealthTaxRate: nil,
                notes: "50% CGT discount for assets held > 12 months."
            )
            
        case .germany:
            return JurisdictionTaxRates(
                jurisdiction: jurisdiction,
                shortTermRate: 0.45, // Income tax rate
                longTermRate: 0.0, // Tax-free after 1 year
                cryptoIncomeRate: 0.45,
                wealthTaxRate: nil,
                notes: "Tax-free after 1 year holding. €600 annual exemption for gains."
            )
            
        case .france:
            return JurisdictionTaxRates(
                jurisdiction: jurisdiction,
                shortTermRate: 0.30, // Flat tax
                longTermRate: 0.30,
                cryptoIncomeRate: 0.30,
                wealthTaxRate: nil,
                notes: "30% flat tax (PFU) on crypto gains."
            )
            
        case .netherlands:
            return JurisdictionTaxRates(
                jurisdiction: jurisdiction,
                shortTermRate: 0.32, // Box 3 wealth tax
                longTermRate: 0.32,
                cryptoIncomeRate: 0.495, // Box 1 income
                wealthTaxRate: 0.32,
                notes: "Wealth tax (Box 3) on total assets above threshold."
            )
            
        case .spain:
            return JurisdictionTaxRates(
                jurisdiction: jurisdiction,
                shortTermRate: 0.28, // Top CGT rate
                longTermRate: 0.28,
                cryptoIncomeRate: 0.47,
                wealthTaxRate: nil,
                notes: "Progressive CGT: 19-28%. Wealth tax varies by region."
            )
            
        case .portugal:
            return JurisdictionTaxRates(
                jurisdiction: jurisdiction,
                shortTermRate: 0.0, // Currently tax-free for individuals
                longTermRate: 0.0,
                cryptoIncomeRate: 0.0,
                wealthTaxRate: nil,
                notes: "Crypto is currently tax-free for individuals. Subject to change."
            )
            
        case .japan:
            return JurisdictionTaxRates(
                jurisdiction: jurisdiction,
                shortTermRate: 0.55, // Max income tax rate
                longTermRate: 0.55, // No LTCG distinction
                cryptoIncomeRate: 0.55,
                wealthTaxRate: nil,
                notes: "Crypto gains taxed as miscellaneous income at up to 55%."
            )
            
        case .singapore:
            return JurisdictionTaxRates(
                jurisdiction: jurisdiction,
                shortTermRate: 0.0, // No capital gains tax
                longTermRate: 0.0,
                cryptoIncomeRate: 0.22, // Income tax if trading
                wealthTaxRate: nil,
                notes: "No capital gains tax for individuals. Professional traders may be taxed."
            )
        }
    }
}

// MARK: - International Export Format

/// Export formats for different tax jurisdictions
public enum InternationalExportFormat: String, CaseIterable, Identifiable {
    case hmrcCapitalGains = "hmrc_cgt"
    case hmrcSelfAssessment = "hmrc_sa"
    case craSchedule3 = "cra_schedule3"
    case atoCapitalGains = "ato_cgt"
    case bzstCrypto = "bzst_crypto"
    case genericInternational = "generic_intl"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .hmrcCapitalGains: return "HMRC Capital Gains (UK)"
        case .hmrcSelfAssessment: return "HMRC Self Assessment (UK)"
        case .craSchedule3: return "CRA Schedule 3 (Canada)"
        case .atoCapitalGains: return "ATO Capital Gains (Australia)"
        case .bzstCrypto: return "BZSt Crypto Report (Germany)"
        case .genericInternational: return "Generic International"
        }
    }
    
    public var jurisdiction: TaxJurisdiction {
        switch self {
        case .hmrcCapitalGains, .hmrcSelfAssessment: return .uk
        case .craSchedule3: return .canada
        case .atoCapitalGains: return .australia
        case .bzstCrypto: return .germany
        case .genericInternational: return .us
        }
    }
    
    public var fileExtension: String { "csv" }
}

// MARK: - International Tax Export Service

/// Service for exporting tax data in international formats
public final class InternationalTaxExportService {
    
    public static let shared = InternationalTaxExportService()
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        return formatter
    }()
    
    private init() {}
    
    // MARK: - Public API
    
    /// Export tax report for a specific jurisdiction
    public func export(
        report: TaxReport,
        format: InternationalExportFormat
    ) -> ExportResult {
        switch format {
        case .hmrcCapitalGains:
            return exportHMRCCapitalGains(report)
        case .hmrcSelfAssessment:
            return exportHMRCSelfAssessment(report)
        case .craSchedule3:
            return exportCRASchedule3(report)
        case .atoCapitalGains:
            return exportATOCapitalGains(report)
        case .bzstCrypto:
            return exportBZStCrypto(report)
        case .genericInternational:
            return exportGenericInternational(report)
        }
    }
    
    // MARK: - UK HMRC Export
    
    private func exportHMRCCapitalGains(_ report: TaxReport) -> ExportResult {
        var csv = "Description,Date Acquired,Date Disposed,Proceeds (GBP),Cost (GBP),Gain/Loss (GBP)\n"
        
        for disposal in report.disposals {
            let line = [
                "\(disposal.quantity) \(disposal.symbol)",
                dateFormatter.string(from: disposal.acquiredDate),
                dateFormatter.string(from: disposal.disposedDate),
                String(format: "%.2f", disposal.totalProceeds),
                String(format: "%.2f", disposal.totalCostBasis),
                String(format: "%.2f", disposal.gain)
            ].joined(separator: ",")
            
            csv += line + "\n"
        }
        
        // Add summary
        csv += "\nSUMMARY\n"
        csv += "Total Disposals,\(report.disposals.count)\n"
        csv += "Total Proceeds,\(String(format: "%.2f", report.disposals.reduce(0) { $0 + $1.totalProceeds }))\n"
        csv += "Total Gains,\(String(format: "%.2f", max(0, report.netCapitalGain)))\n"
        csv += "Total Losses,\(String(format: "%.2f", abs(min(0, report.netCapitalGain))))\n"
        csv += "\nNote: Convert USD amounts to GBP using the exchange rate on the date of each transaction.\n"
        csv += "Annual Exempt Amount (2023-24): £6,000\n"
        
        return ExportResult(
            data: csv,
            filename: "HMRC_CapitalGains_\(report.taxYear.year).csv",
            format: .genericCSV
        )
    }
    
    private func exportHMRCSelfAssessment(_ report: TaxReport) -> ExportResult {
        var csv = "SA108 - Capital Gains Summary\n\n"
        
        // Section for crypto assets
        csv += "Crypto Asset Disposals\n"
        csv += "Asset,Number Disposed,Disposal Proceeds,Allowable Costs,Gain/Loss\n"
        
        // Group by symbol
        let bySymbol = Dictionary(grouping: report.disposals) { $0.symbol }
        for (symbol, disposals) in bySymbol.sorted(by: { $0.key < $1.key }) {
            let count = disposals.reduce(0) { $0 + $1.quantity }
            let proceeds = disposals.reduce(0) { $0 + $1.totalProceeds }
            let costs = disposals.reduce(0) { $0 + $1.totalCostBasis }
            let gain = proceeds - costs
            
            csv += "\(symbol),\(String(format: "%.4f", count)),\(String(format: "%.2f", proceeds)),\(String(format: "%.2f", costs)),\(String(format: "%.2f", gain))\n"
        }
        
        csv += "\nTotal Capital Gains,\(String(format: "%.2f", report.netCapitalGain))\n"
        
        // Income section
        if !report.incomeEvents.isEmpty {
            csv += "\nCrypto Income (include in employment or self-employment income)\n"
            csv += "Type,Amount (GBP)\n"
            
            let incomeBySource = Dictionary(grouping: report.incomeEvents) { $0.source }
            for (source, events) in incomeBySource {
                let total = events.reduce(0) { $0 + $1.totalValue }
                csv += "\(source.displayName),\(String(format: "%.2f", total))\n"
            }
        }
        
        return ExportResult(
            data: csv,
            filename: "HMRC_SA108_\(report.taxYear.year).csv",
            format: .genericCSV
        )
    }
    
    // MARK: - Canada CRA Export
    
    private func exportCRASchedule3(_ report: TaxReport) -> ExportResult {
        var csv = "Schedule 3 - Capital Gains (or Losses)\n"
        csv += "Virtual Currency / Cryptocurrency\n\n"
        
        csv += "Description,Year Acquired,Proceeds of Disposition,Adjusted Cost Base,Outlays and Expenses,Gain (or Loss)\n"
        
        for disposal in report.disposals {
            let year = Calendar.current.component(.year, from: disposal.acquiredDate)
            let line = [
                "\(disposal.quantity) \(disposal.symbol)",
                String(year),
                String(format: "%.2f", disposal.totalProceeds),
                String(format: "%.2f", disposal.totalCostBasis),
                "0.00", // Expenses
                String(format: "%.2f", disposal.gain)
            ].joined(separator: ",")
            
            csv += line + "\n"
        }
        
        // Calculate taxable amount (50% inclusion rate)
        let totalGain = report.netCapitalGain
        let taxableGain = totalGain > 0 ? totalGain * 0.5 : totalGain
        
        csv += "\nSummary\n"
        csv += "Total Capital Gains (Line 12700),\(String(format: "%.2f", max(0, totalGain)))\n"
        csv += "Total Capital Losses,\(String(format: "%.2f", abs(min(0, totalGain))))\n"
        csv += "Taxable Capital Gains (50%),\(String(format: "%.2f", max(0, taxableGain)))\n"
        
        csv += "\nNote: In Canada, 50% of capital gains are taxable. Report on Schedule 3 and include on Line 12700 of your T1.\n"
        
        return ExportResult(
            data: csv,
            filename: "CRA_Schedule3_\(report.taxYear.year).csv",
            format: .genericCSV
        )
    }
    
    // MARK: - Australia ATO Export
    
    private func exportATOCapitalGains(_ report: TaxReport) -> ExportResult {
        var csv = "ATO Capital Gains Tax Report - Cryptocurrency\n\n"
        
        csv += "Asset,Date Acquired,Date Sold,Proceeds (AUD),Cost Base (AUD),Capital Gain/Loss,CGT Discount Applicable\n"
        
        for disposal in report.disposals {
            let discountApplicable = disposal.gainType == .longTerm && disposal.gain > 0 ? "Yes" : "No"
            
            let line = [
                "\(disposal.quantity) \(disposal.symbol)",
                dateFormatter.string(from: disposal.acquiredDate),
                dateFormatter.string(from: disposal.disposedDate),
                String(format: "%.2f", disposal.totalProceeds),
                String(format: "%.2f", disposal.totalCostBasis),
                String(format: "%.2f", disposal.gain),
                discountApplicable
            ].joined(separator: ",")
            
            csv += line + "\n"
        }
        
        // Calculate with CGT discount
        let shortTermGains = report.disposals.filter { $0.gainType == .shortTerm && $0.gain > 0 }.reduce(0) { $0 + $1.gain }
        let longTermGains = report.disposals.filter { $0.gainType == .longTerm && $0.gain > 0 }.reduce(0) { $0 + $1.gain }
        let losses = report.disposals.filter { $0.gain < 0 }.reduce(0) { $0 + abs($1.gain) }
        
        // Apply 50% discount to long-term gains
        let discountedLongTerm = longTermGains * 0.5
        let netGain = shortTermGains + discountedLongTerm - losses
        
        csv += "\nCGT Summary\n"
        csv += "Short-term capital gains,\(String(format: "%.2f", shortTermGains))\n"
        csv += "Long-term capital gains (before discount),\(String(format: "%.2f", longTermGains))\n"
        csv += "CGT Discount (50%),\(String(format: "%.2f", longTermGains * 0.5))\n"
        csv += "Long-term gains (after discount),\(String(format: "%.2f", discountedLongTerm))\n"
        csv += "Capital losses,\(String(format: "%.2f", losses))\n"
        csv += "Net capital gain,\(String(format: "%.2f", max(0, netGain)))\n"
        
        csv += "\nNote: Assets held for more than 12 months may be eligible for the 50% CGT discount.\n"
        
        return ExportResult(
            data: csv,
            filename: "ATO_CGT_\(report.taxYear.year).csv",
            format: .genericCSV
        )
    }
    
    // MARK: - Germany BZSt Export
    
    private func exportBZStCrypto(_ report: TaxReport) -> ExportResult {
        var csv = "Kryptowährungen - Steuererklärung\n"
        csv += "Anlage SO (Sonstige Einkünfte)\n\n"
        
        csv += "Bezeichnung,Anschaffungsdatum,Veräußerungsdatum,Veräußerungserlös (EUR),Anschaffungskosten (EUR),Gewinn/Verlust (EUR),Haltedauer (Tage),Steuerfrei\n"
        
        for disposal in report.disposals {
            let taxFree = disposal.holdingPeriodDays >= 365 ? "Ja" : "Nein"
            
            let line = [
                "\(disposal.quantity) \(disposal.symbol)",
                dateFormatter.string(from: disposal.acquiredDate),
                dateFormatter.string(from: disposal.disposedDate),
                String(format: "%.2f", disposal.totalProceeds),
                String(format: "%.2f", disposal.totalCostBasis),
                String(format: "%.2f", disposal.gain),
                String(disposal.holdingPeriodDays),
                taxFree
            ].joined(separator: ",")
            
            csv += line + "\n"
        }
        
        // Calculate taxable gains (only short-term in Germany)
        let shortTermGains = report.disposals
            .filter { $0.holdingPeriodDays < 365 && $0.gain > 0 }
            .reduce(0) { $0 + $1.gain }
        
        let shortTermLosses = report.disposals
            .filter { $0.holdingPeriodDays < 365 && $0.gain < 0 }
            .reduce(0) { $0 + abs($1.gain) }
        
        let longTermGains = report.disposals
            .filter { $0.holdingPeriodDays >= 365 }
            .reduce(0) { $0 + $1.gain }
        
        csv += "\nZusammenfassung\n"
        csv += "Kurzfristige Gewinne (< 1 Jahr),\(String(format: "%.2f", shortTermGains))\n"
        csv += "Kurzfristige Verluste,\(String(format: "%.2f", shortTermLosses))\n"
        csv += "Netto steuerpflichtiger Gewinn,\(String(format: "%.2f", max(0, shortTermGains - shortTermLosses)))\n"
        csv += "Steuerfreie Gewinne (> 1 Jahr),\(String(format: "%.2f", max(0, longTermGains)))\n"
        csv += "Freigrenze (falls unter 600 EUR),\(shortTermGains - shortTermLosses < 600 ? "Steuerfrei" : "Steuerpflichtig")\n"
        
        csv += "\nHinweis: In Deutschland sind Krypto-Gewinne nach einem Jahr Haltedauer steuerfrei. Es gibt eine Freigrenze von 600 EUR pro Jahr.\n"
        
        return ExportResult(
            data: csv,
            filename: "BZSt_Krypto_\(report.taxYear.year).csv",
            format: .genericCSV
        )
    }
    
    // MARK: - Generic International Export
    
    private func exportGenericInternational(_ report: TaxReport) -> ExportResult {
        var csv = "International Crypto Tax Report\n"
        csv += "Tax Year: \(report.taxYear.year)\n"
        csv += "Note: Convert USD amounts to your local currency using appropriate exchange rates.\n\n"
        
        csv += "CAPITAL GAINS TRANSACTIONS\n"
        csv += "Asset,Quantity,Date Acquired,Date Disposed,Holding Period (Days),Cost Basis (USD),Proceeds (USD),Gain/Loss (USD),Short/Long Term\n"
        
        for disposal in report.disposals {
            let term = disposal.gainType == .shortTerm ? "Short" : "Long"
            
            let line = [
                disposal.symbol,
                String(format: "%.8f", disposal.quantity),
                dateFormatter.string(from: disposal.acquiredDate),
                dateFormatter.string(from: disposal.disposedDate),
                String(disposal.holdingPeriodDays),
                String(format: "%.2f", disposal.totalCostBasis),
                String(format: "%.2f", disposal.totalProceeds),
                String(format: "%.2f", disposal.gain),
                term
            ].joined(separator: ",")
            
            csv += line + "\n"
        }
        
        // Income section
        if !report.incomeEvents.isEmpty {
            csv += "\nCRYPTO INCOME\n"
            csv += "Type,Asset,Quantity,Date,Fair Market Value (USD)\n"
            
            for income in report.incomeEvents {
                let line = [
                    income.source.displayName,
                    income.symbol,
                    String(format: "%.8f", income.quantity),
                    dateFormatter.string(from: income.date),
                    String(format: "%.2f", income.totalValue)
                ].joined(separator: ",")
                
                csv += line + "\n"
            }
        }
        
        csv += "\nSUMMARY\n"
        csv += "Total Short-Term Gain/Loss,\(String(format: "%.2f", report.shortTermGain))\n"
        csv += "Total Long-Term Gain/Loss,\(String(format: "%.2f", report.longTermGain))\n"
        csv += "Total Capital Gain/Loss,\(String(format: "%.2f", report.netCapitalGain))\n"
        csv += "Total Crypto Income,\(String(format: "%.2f", report.totalIncome))\n"
        
        return ExportResult(
            data: csv,
            filename: "CryptoTax_International_\(report.taxYear.year).csv",
            format: .genericCSV
        )
    }
}
