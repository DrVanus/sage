//
//  TaxCSVImportService.swift
//  CryptoSage
//
//  CSV import service for exchange transaction history.
//

import Foundation
import UniformTypeIdentifiers

// MARK: - Supported Exchange Formats

/// Supported exchange CSV formats
public enum ExchangeCSVFormat: String, CaseIterable, Identifiable {
    case coinbase = "coinbase"
    case coinbasePro = "coinbase_pro"
    case binance = "binance"
    case kraken = "kraken"
    case gemini = "gemini"
    case kucoin = "kucoin"
    case generic = "generic"
    
    public var id: String { rawValue }
    
    public var displayName: String {
        switch self {
        case .coinbase: return "Coinbase"
        case .coinbasePro: return "Coinbase Pro"
        case .binance: return "Binance"
        case .kraken: return "Kraken"
        case .gemini: return "Gemini"
        case .kucoin: return "KuCoin"
        case .generic: return "Generic CSV"
        }
    }
    
    public var description: String {
        switch self {
        case .coinbase: return "Standard Coinbase transaction export"
        case .coinbasePro: return "Coinbase Pro fills export"
        case .binance: return "Binance trade history export"
        case .kraken: return "Kraken ledger export"
        case .gemini: return "Gemini transaction history"
        case .kucoin: return "KuCoin trade history"
        case .generic: return "Custom format with required columns"
        }
    }
    
    /// Required columns for this format
    public var requiredColumns: [String] {
        switch self {
        case .coinbase:
            return ["Timestamp", "Transaction Type", "Asset", "Quantity Transacted", "Spot Price at Transaction"]
        case .coinbasePro:
            return ["time", "side", "size", "size unit", "price", "fee"]
        case .binance:
            return ["Date(UTC)", "Pair", "Side", "Price", "Executed", "Amount", "Fee"]
        case .kraken:
            return ["time", "type", "asset", "amount", "fee", "balance"]
        case .gemini:
            return ["Date", "Type", "Symbol", "Amount", "Price", "Fee"]
        case .kucoin:
            return ["Time", "Symbol", "Side", "Price", "Filled", "Fee"]
        case .generic:
            return ["date", "type", "symbol", "quantity", "price"]
        }
    }
}

// MARK: - Imported Transaction

/// A transaction parsed from CSV
public struct ImportedTransaction: Identifiable, Codable {
    public let id: UUID
    public let date: Date
    public let type: ImportedTransactionType
    public let symbol: String
    public let quantity: Double
    public let pricePerUnit: Double
    public let fee: Double
    public let feeAsset: String?
    public let exchange: String
    public let rawData: [String: String]?
    public let walletId: String?
    
    public init(
        id: UUID = UUID(),
        date: Date,
        type: ImportedTransactionType,
        symbol: String,
        quantity: Double,
        pricePerUnit: Double,
        fee: Double = 0,
        feeAsset: String? = nil,
        exchange: String,
        rawData: [String: String]? = nil,
        walletId: String? = nil
    ) {
        self.id = id
        self.date = date
        self.type = type
        self.symbol = symbol.uppercased()
        self.quantity = quantity
        self.pricePerUnit = pricePerUnit
        self.fee = fee
        self.feeAsset = feeAsset
        self.exchange = exchange
        self.rawData = rawData
        self.walletId = walletId
    }
    
    /// Total value of this transaction
    public var totalValue: Double {
        quantity * pricePerUnit
    }
    
    /// Whether this is a buy/acquisition
    public var isBuy: Bool {
        type.isBuy
    }
    
    /// Whether this is a sell/disposal
    public var isSell: Bool {
        type.isSell
    }
    
    /// Whether this is income
    public var isIncome: Bool {
        type.isIncome
    }
}

/// Type of imported transaction
public enum ImportedTransactionType: String, Codable {
    case buy = "buy"
    case sell = "sell"
    case trade = "trade"
    case send = "send"
    case receive = "receive"
    case staking = "staking"
    case mining = "mining"
    case airdrop = "airdrop"
    case interest = "interest"
    case reward = "reward"
    case gift = "gift"
    case fork = "fork"
    case fee = "fee"
    case unknown = "unknown"
    
    public var isBuy: Bool {
        switch self {
        case .buy, .receive, .staking, .mining, .airdrop, .interest, .reward, .gift, .fork:
            return true
        default:
            return false
        }
    }
    
    public var isSell: Bool {
        switch self {
        case .sell, .send, .trade:
            return true
        default:
            return false
        }
    }
    
    public var isIncome: Bool {
        switch self {
        case .staking, .mining, .airdrop, .interest, .reward:
            return true
        default:
            return false
        }
    }
    
    /// Convert to TaxLotSource
    public var taxLotSource: TaxLotSource {
        switch self {
        case .buy: return .purchase
        case .trade: return .trade
        case .staking: return .staking
        case .mining: return .mining
        case .airdrop: return .airdrop
        case .interest: return .interest
        case .reward: return .rewards
        case .gift: return .gift
        case .fork: return .fork
        case .receive: return .transfer
        default: return .unknown
        }
    }
}

// MARK: - Import Result

/// Result of Tax CSV import operation
public struct TaxCSVImportResult {
    public let transactions: [ImportedTransaction]
    public let errors: [TaxCSVImportError]
    public let skippedRows: Int
    public let format: ExchangeCSVFormat
    
    public var successCount: Int { transactions.count }
    public var errorCount: Int { errors.count }
    public var hasErrors: Bool { !errors.isEmpty }
}

/// Tax CSV import error
public struct TaxCSVImportError: Identifiable {
    public let id = UUID()
    public let row: Int
    public let message: String
    public let rawData: String?
}

// MARK: - Tax CSV Import Service

/// Service for importing CSV transaction files from exchanges
public final class TaxCSVImportService {
    
    public static let shared = TaxCSVImportService()
    
    private let dateFormatters: [DateFormatter] = {
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd",
            "MM/dd/yyyy HH:mm:ss",
            "MM/dd/yyyy",
            "dd/MM/yyyy HH:mm:ss",
            "dd/MM/yyyy",
            "yyyy/MM/dd HH:mm:ss",
            "MMM dd, yyyy, h:mm:ss a",
            "MMM dd, yyyy"
        ]
        return formats.map { format in
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            return formatter
        }
    }()
    
    private init() {}
    
    // MARK: - Public API
    
    /// Import transactions from CSV data
    public func importCSV(
        data: Data,
        format: ExchangeCSVFormat,
        walletId: String? = nil
    ) -> TaxCSVImportResult {
        guard let csvString = String(data: data, encoding: .utf8) else {
            return TaxCSVImportResult(
                transactions: [],
                errors: [TaxCSVImportError(row: 0, message: "Unable to read file as UTF-8 text", rawData: nil)],
                skippedRows: 0,
                format: format
            )
        }
        
        return importCSV(string: csvString, format: format, walletId: walletId)
    }
    
    /// Import transactions from CSV string
    public func importCSV(
        string: String,
        format: ExchangeCSVFormat,
        walletId: String? = nil
    ) -> TaxCSVImportResult {
        let lines = parseCSVLines(string)
        guard lines.count > 1 else {
            return TaxCSVImportResult(
                transactions: [],
                errors: [TaxCSVImportError(row: 0, message: "CSV file is empty or has no data rows", rawData: nil)],
                skippedRows: 0,
                format: format
            )
        }
        
        let headers = lines[0]
        var transactions: [ImportedTransaction] = []
        var errors: [TaxCSVImportError] = []
        var skippedRows = 0
        
        for (index, row) in lines.dropFirst().enumerated() {
            let rowNumber = index + 2 // Account for header row and 1-based indexing
            
            // Skip empty rows
            if row.allSatisfy({ $0.isEmpty }) {
                skippedRows += 1
                continue
            }
            
            do {
                if let transaction = try parseRow(row, headers: headers, format: format, exchange: format.displayName, walletId: walletId) {
                    transactions.append(transaction)
                } else {
                    skippedRows += 1
                }
            } catch {
                errors.append(TaxCSVImportError(
                    row: rowNumber,
                    message: error.localizedDescription,
                    rawData: row.joined(separator: ",")
                ))
            }
        }
        
        return TaxCSVImportResult(
            transactions: transactions.sorted { $0.date < $1.date },
            errors: errors,
            skippedRows: skippedRows,
            format: format
        )
    }
    
    /// Auto-detect CSV format from headers
    public func detectFormat(from data: Data) -> ExchangeCSVFormat? {
        guard let csvString = String(data: data, encoding: .utf8) else { return nil }
        return detectFormat(from: csvString)
    }
    
    public func detectFormat(from string: String) -> ExchangeCSVFormat? {
        let lines = parseCSVLines(string)
        guard let headers = lines.first else { return nil }
        
        let headerSet = Set(headers.map { $0.lowercased() })
        
        // Check for Coinbase format
        if headerSet.contains("transaction type") && headerSet.contains("spot price at transaction") {
            return .coinbase
        }
        
        // Check for Coinbase Pro format
        if headerSet.contains("size unit") && headerSet.contains("portfolio") {
            return .coinbasePro
        }
        
        // Check for Binance format
        if headerSet.contains("date(utc)") && headerSet.contains("pair") {
            return .binance
        }
        
        // Check for Kraken format
        if headerSet.contains("refid") && headerSet.contains("txid") && headerSet.contains("asset") {
            return .kraken
        }
        
        // Check for Gemini format
        if headerSet.contains("specification") && headerSet.contains("symbol") {
            return .gemini
        }
        
        // Check for KuCoin format
        if headerSet.contains("filled") && headerSet.contains("order type") {
            return .kucoin
        }
        
        // Check for generic format
        if headerSet.contains("date") && headerSet.contains("type") && headerSet.contains("symbol") {
            return .generic
        }
        
        return nil
    }
    
    // MARK: - Private Helpers
    
    private func parseCSVLines(_ csv: String) -> [[String]] {
        var lines: [[String]] = []
        var currentLine: [String] = []
        var currentField = ""
        var inQuotes = false
        
        for char in csv {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                currentLine.append(currentField.trimmingCharacters(in: .whitespaces))
                currentField = ""
            } else if (char == "\n" || char == "\r") && !inQuotes {
                if !currentField.isEmpty || !currentLine.isEmpty {
                    currentLine.append(currentField.trimmingCharacters(in: .whitespaces))
                    if !currentLine.allSatisfy({ $0.isEmpty }) {
                        lines.append(currentLine)
                    }
                    currentLine = []
                    currentField = ""
                }
            } else {
                currentField.append(char)
            }
        }
        
        // Handle last line
        if !currentField.isEmpty || !currentLine.isEmpty {
            currentLine.append(currentField.trimmingCharacters(in: .whitespaces))
            if !currentLine.allSatisfy({ $0.isEmpty }) {
                lines.append(currentLine)
            }
        }
        
        return lines
    }
    
    private func parseRow(
        _ row: [String],
        headers: [String],
        format: ExchangeCSVFormat,
        exchange: String,
        walletId: String?
    ) throws -> ImportedTransaction? {
        // Create dictionary from row
        var data: [String: String] = [:]
        for (index, header) in headers.enumerated() {
            if index < row.count {
                data[header.lowercased()] = row[index]
            }
        }
        
        switch format {
        case .coinbase:
            return try parseCoinbaseRow(data, exchange: exchange, walletId: walletId)
        case .coinbasePro:
            return try parseCoinbaseProRow(data, exchange: exchange, walletId: walletId)
        case .binance:
            return try parseBinanceRow(data, exchange: exchange, walletId: walletId)
        case .kraken:
            return try parseKrakenRow(data, exchange: exchange, walletId: walletId)
        case .gemini:
            return try parseGeminiRow(data, exchange: exchange, walletId: walletId)
        case .kucoin:
            return try parseKuCoinRow(data, exchange: exchange, walletId: walletId)
        case .generic:
            return try parseGenericRow(data, exchange: exchange, walletId: walletId)
        }
    }
    
    // MARK: - Exchange-Specific Parsers
    
    private func parseCoinbaseRow(_ data: [String: String], exchange: String, walletId: String?) throws -> ImportedTransaction? {
        guard let timestamp = data["timestamp"],
              let txType = data["transaction type"],
              let asset = data["asset"],
              let quantityStr = data["quantity transacted"],
              let spotPriceStr = data["spot price at transaction"] else {
            throw ImportError.missingRequiredField
        }
        
        guard let date = parseDate(timestamp) else {
            throw ImportError.invalidDateFormat(timestamp)
        }
        
        guard let quantity = Double(quantityStr.replacingOccurrences(of: ",", with: "")) else {
            throw ImportError.invalidNumber(quantityStr)
        }
        
        let spotPrice = Double(spotPriceStr.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")) ?? 0
        
        let type = mapCoinbaseType(txType)
        
        // Skip certain transaction types
        if type == .unknown && !["buy", "sell", "send", "receive"].contains(txType.lowercased()) {
            return nil
        }
        
        let fee = Double(data["fees"]?.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "") ?? "0") ?? 0
        
        return ImportedTransaction(
            date: date,
            type: type,
            symbol: asset,
            quantity: abs(quantity),
            pricePerUnit: spotPrice,
            fee: fee,
            feeAsset: "USD",
            exchange: exchange,
            rawData: data,
            walletId: walletId
        )
    }
    
    private func parseCoinbaseProRow(_ data: [String: String], exchange: String, walletId: String?) throws -> ImportedTransaction? {
        guard let time = data["time"],
              let side = data["side"],
              let sizeStr = data["size"],
              let sizeUnit = data["size unit"],
              let priceStr = data["price"] else {
            throw ImportError.missingRequiredField
        }
        
        guard let date = parseDate(time) else {
            throw ImportError.invalidDateFormat(time)
        }
        
        guard let size = Double(sizeStr.replacingOccurrences(of: ",", with: "")) else {
            throw ImportError.invalidNumber(sizeStr)
        }
        
        let price = Double(priceStr.replacingOccurrences(of: ",", with: "")) ?? 0
        let fee = Double(data["fee"]?.replacingOccurrences(of: ",", with: "") ?? "0") ?? 0
        
        let type: ImportedTransactionType = side.lowercased() == "buy" ? .buy : .sell
        
        return ImportedTransaction(
            date: date,
            type: type,
            symbol: sizeUnit,
            quantity: size,
            pricePerUnit: price,
            fee: fee,
            feeAsset: "USD",
            exchange: "Coinbase Pro",
            rawData: data,
            walletId: walletId
        )
    }
    
    private func parseBinanceRow(_ data: [String: String], exchange: String, walletId: String?) throws -> ImportedTransaction? {
        guard let dateStr = data["date(utc)"],
              let pair = data["pair"],
              let side = data["side"],
              let priceStr = data["price"],
              let executedStr = data["executed"] else {
            throw ImportError.missingRequiredField
        }
        
        guard let date = parseDate(dateStr) else {
            throw ImportError.invalidDateFormat(dateStr)
        }
        
        // Parse pair (e.g., "BTCUSDT" -> "BTC")
        let symbol = extractBaseAsset(from: pair)
        
        guard let executed = parseQuantityWithUnit(executedStr) else {
            throw ImportError.invalidNumber(executedStr)
        }
        
        let price = Double(priceStr.replacingOccurrences(of: ",", with: "")) ?? 0
        
        let feeStr = data["fee"] ?? "0"
        let (feeAmount, feeAsset) = parseFeeWithAsset(feeStr)
        
        let type: ImportedTransactionType = side.lowercased() == "buy" ? .buy : .sell
        
        return ImportedTransaction(
            date: date,
            type: type,
            symbol: symbol,
            quantity: executed,
            pricePerUnit: price,
            fee: feeAmount,
            feeAsset: feeAsset,
            exchange: exchange,
            rawData: data,
            walletId: walletId
        )
    }
    
    private func parseKrakenRow(_ data: [String: String], exchange: String, walletId: String?) throws -> ImportedTransaction? {
        guard let time = data["time"],
              let txType = data["type"],
              let asset = data["asset"],
              let amountStr = data["amount"] else {
            throw ImportError.missingRequiredField
        }
        
        // Skip non-trade entries (deposits, withdrawals handled separately)
        let validTypes = ["trade", "buy", "sell", "staking", "earn"]
        if !validTypes.contains(txType.lowercased()) {
            return nil
        }
        
        guard let date = parseDate(time) else {
            throw ImportError.invalidDateFormat(time)
        }
        
        guard let amount = Double(amountStr.replacingOccurrences(of: ",", with: "")) else {
            throw ImportError.invalidNumber(amountStr)
        }
        
        // Kraken uses negative amounts for sells
        let type: ImportedTransactionType = amount < 0 ? .sell : .buy
        
        let fee = Double(data["fee"]?.replacingOccurrences(of: ",", with: "") ?? "0") ?? 0
        
        // Kraken uses asset codes like XXBT for BTC, XETH for ETH
        let normalizedAsset = normalizeKrakenAsset(asset)
        
        return ImportedTransaction(
            date: date,
            type: type,
            symbol: normalizedAsset,
            quantity: abs(amount),
            pricePerUnit: 0, // Kraken ledger doesn't include price, would need to calculate
            fee: fee,
            feeAsset: normalizedAsset,
            exchange: exchange,
            rawData: data,
            walletId: walletId
        )
    }
    
    private func parseGeminiRow(_ data: [String: String], exchange: String, walletId: String?) throws -> ImportedTransaction? {
        guard let dateStr = data["date"],
              let txType = data["type"],
              let symbol = data["symbol"],
              let amountStr = data["amount"] else {
            throw ImportError.missingRequiredField
        }
        
        guard let date = parseDate(dateStr) else {
            throw ImportError.invalidDateFormat(dateStr)
        }
        
        // Parse amount (may include currency symbol)
        guard let amount = parseQuantityWithUnit(amountStr) else {
            throw ImportError.invalidNumber(amountStr)
        }
        
        let price = Double(data["price"]?.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "") ?? "0") ?? 0
        let fee = Double(data["fee"]?.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "") ?? "0") ?? 0
        
        let type = mapGeminiType(txType)
        
        return ImportedTransaction(
            date: date,
            type: type,
            symbol: extractBaseAsset(from: symbol),
            quantity: abs(amount),
            pricePerUnit: price,
            fee: fee,
            feeAsset: "USD",
            exchange: exchange,
            rawData: data,
            walletId: walletId
        )
    }
    
    private func parseKuCoinRow(_ data: [String: String], exchange: String, walletId: String?) throws -> ImportedTransaction? {
        guard let time = data["time"],
              let symbol = data["symbol"],
              let side = data["side"],
              let priceStr = data["price"],
              let filledStr = data["filled"] else {
            throw ImportError.missingRequiredField
        }
        
        guard let date = parseDate(time) else {
            throw ImportError.invalidDateFormat(time)
        }
        
        guard let filled = parseQuantityWithUnit(filledStr) else {
            throw ImportError.invalidNumber(filledStr)
        }
        
        let price = Double(priceStr.replacingOccurrences(of: ",", with: "")) ?? 0
        
        let feeStr = data["fee"] ?? "0"
        let (feeAmount, feeAsset) = parseFeeWithAsset(feeStr)
        
        let type: ImportedTransactionType = side.lowercased() == "buy" ? .buy : .sell
        let baseAsset = extractBaseAsset(from: symbol.replacingOccurrences(of: "-", with: ""))
        
        return ImportedTransaction(
            date: date,
            type: type,
            symbol: baseAsset,
            quantity: filled,
            pricePerUnit: price,
            fee: feeAmount,
            feeAsset: feeAsset,
            exchange: exchange,
            rawData: data,
            walletId: walletId
        )
    }
    
    private func parseGenericRow(_ data: [String: String], exchange: String, walletId: String?) throws -> ImportedTransaction? {
        guard let dateStr = data["date"],
              let typeStr = data["type"],
              let symbol = data["symbol"],
              let quantityStr = data["quantity"],
              let priceStr = data["price"] else {
            throw ImportError.missingRequiredField
        }
        
        guard let date = parseDate(dateStr) else {
            throw ImportError.invalidDateFormat(dateStr)
        }
        
        guard let quantity = Double(quantityStr.replacingOccurrences(of: ",", with: "")) else {
            throw ImportError.invalidNumber(quantityStr)
        }
        
        let price = Double(priceStr.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")) ?? 0
        let fee = Double(data["fee"]?.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "") ?? "0") ?? 0
        
        let type = mapGenericType(typeStr)
        
        return ImportedTransaction(
            date: date,
            type: type,
            symbol: symbol.uppercased(),
            quantity: abs(quantity),
            pricePerUnit: price,
            fee: fee,
            feeAsset: data["fee_asset"]?.uppercased() ?? "USD",
            exchange: data["exchange"] ?? "Unknown",
            rawData: data,
            walletId: walletId
        )
    }
    
    // MARK: - Utility Functions
    
    private func parseDate(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        for formatter in dateFormatters {
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }
    
    private func parseQuantityWithUnit(_ string: String) -> Double? {
        // Remove common currency symbols and letters, keep numbers and decimal
        let cleaned = string.replacingOccurrences(of: "[^0-9.-]", with: "", options: .regularExpression)
        return Double(cleaned)
    }
    
    private func parseFeeWithAsset(_ string: String) -> (Double, String?) {
        let components = string.components(separatedBy: " ")
        if components.count >= 2, let amount = Double(components[0].replacingOccurrences(of: ",", with: "")) {
            return (amount, components[1])
        }
        if let amount = parseQuantityWithUnit(string) {
            return (amount, nil)
        }
        return (0, nil)
    }
    
    private func extractBaseAsset(from pair: String) -> String {
        // Common quote currencies to strip
        let quoteCurrencies = ["USDT", "USDC", "USD", "EUR", "GBP", "BTC", "ETH", "BNB", "BUSD"]
        
        var result = pair.uppercased()
        for quote in quoteCurrencies {
            if result.hasSuffix(quote) {
                result = String(result.dropLast(quote.count))
                break
            }
        }
        return result.isEmpty ? pair : result
    }
    
    private func normalizeKrakenAsset(_ asset: String) -> String {
        // Kraken uses X prefix for crypto (XXBT = BTC, XETH = ETH)
        // and Z prefix for fiat (ZUSD, ZEUR)
        var normalized = asset.uppercased()
        
        // Handle special cases
        let krakenMapping: [String: String] = [
            "XXBT": "BTC",
            "XBT": "BTC",
            "XETH": "ETH",
            "XXRP": "XRP",
            "XXLM": "XLM",
            "XLTC": "LTC",
            "ZUSD": "USD",
            "ZEUR": "EUR",
            "ZGBP": "GBP"
        ]
        
        if let mapped = krakenMapping[normalized] {
            return mapped
        }
        
        // Remove X or Z prefix if present
        if normalized.hasPrefix("X") || normalized.hasPrefix("Z") {
            normalized = String(normalized.dropFirst())
        }
        
        return normalized
    }
    
    private func mapCoinbaseType(_ type: String) -> ImportedTransactionType {
        switch type.lowercased() {
        case "buy", "advanced trade buy": return .buy
        case "sell", "advanced trade sell": return .sell
        case "send": return .send
        case "receive": return .receive
        case "rewards income", "staking income": return .staking
        case "coinbase earn": return .reward
        case "interest": return .interest
        case "inflation reward": return .reward
        default: return .unknown
        }
    }
    
    private func mapGeminiType(_ type: String) -> ImportedTransactionType {
        switch type.lowercased() {
        case "buy": return .buy
        case "sell": return .sell
        case "credit", "deposit": return .receive
        case "debit", "withdrawal": return .send
        case "interest credit": return .interest
        case "staking reward": return .staking
        default: return .unknown
        }
    }
    
    private func mapGenericType(_ type: String) -> ImportedTransactionType {
        switch type.lowercased() {
        case "buy", "purchase": return .buy
        case "sell", "sale": return .sell
        case "trade", "swap": return .trade
        case "send", "transfer_out", "withdrawal": return .send
        case "receive", "transfer_in", "deposit": return .receive
        case "staking", "stake_reward": return .staking
        case "mining", "mine_reward": return .mining
        case "airdrop": return .airdrop
        case "interest", "lending": return .interest
        case "reward", "bonus": return .reward
        case "gift": return .gift
        case "fork": return .fork
        default: return .unknown
        }
    }
}

// MARK: - Import Error

enum ImportError: LocalizedError {
    case missingRequiredField
    case invalidDateFormat(String)
    case invalidNumber(String)
    case unsupportedFormat
    
    var errorDescription: String? {
        switch self {
        case .missingRequiredField:
            return "Missing required field"
        case .invalidDateFormat(let value):
            return "Invalid date format: \(value)"
        case .invalidNumber(let value):
            return "Invalid number: \(value)"
        case .unsupportedFormat:
            return "Unsupported CSV format"
        }
    }
}

// MARK: - TaxLotManager Extension

extension TaxLotManager {
    
    /// Import transactions from CSV import result
    public func importFromCSV(_ result: TaxCSVImportResult) -> (lots: Int, disposals: Int, income: Int) {
        var lotsCreated = 0
        var disposalsCreated = 0
        var incomeCreated = 0
        
        for tx in result.transactions {
            if tx.isBuy {
                if tx.isIncome {
                    // Create income event and lot
                    _ = createLotFromIncome(
                        symbol: tx.symbol,
                        quantity: tx.quantity,
                        fairMarketValue: tx.pricePerUnit,
                        date: tx.date,
                        source: tx.type.taxLotSource,
                        exchange: tx.exchange,
                        walletId: tx.walletId
                    )
                    incomeCreated += 1
                } else {
                    // Create acquisition lot
                    _ = createLotFromPurchase(
                        symbol: tx.symbol,
                        quantity: tx.quantity,
                        pricePerUnit: tx.pricePerUnit,
                        date: tx.date,
                        exchange: tx.exchange,
                        fee: tx.fee,
                        walletId: tx.walletId
                    )
                }
                lotsCreated += 1
            } else if tx.isSell {
                // Process as disposal via TaxEngine
                let engine = TaxEngine.shared
                let newDisposals = engine.processSale(
                    symbol: tx.symbol,
                    quantity: tx.quantity,
                    proceedsPerUnit: tx.pricePerUnit,
                    date: tx.date,
                    exchange: tx.exchange
                )
                disposalsCreated += newDisposals.count
            }
        }
        
        return (lotsCreated, disposalsCreated, incomeCreated)
    }
}
