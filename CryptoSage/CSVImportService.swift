//
//  CSVImportService.swift
//  CryptoSage
//
//  Service for importing cryptocurrency transactions from CSV files.
//  Supports common export formats from popular exchanges.
//

import Foundation
import UniformTypeIdentifiers

// MARK: - CSV Import Error

enum CSVImportError: LocalizedError {
    case fileNotFound
    case invalidFormat
    case emptyFile
    case parsingFailed(row: Int, reason: String)
    case unsupportedFormat
    case missingRequiredColumns([String])
    
    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "CSV file not found"
        case .invalidFormat:
            return "Invalid CSV format"
        case .emptyFile:
            return "The CSV file is empty"
        case .parsingFailed(let row, let reason):
            return "Failed to parse row \(row): \(reason)"
        case .unsupportedFormat:
            return "Unsupported CSV format"
        case .missingRequiredColumns(let columns):
            return "Missing required columns: \(columns.joined(separator: ", "))"
        }
    }
}

// MARK: - CSV Format Detection

enum CSVFormat: String, CaseIterable {
    case coinbase = "Coinbase"
    case binance = "Binance"
    case kraken = "Kraken"
    case generic = "Generic"
    case kucoin = "KuCoin"
    case gemini = "Gemini"
    case coingecko = "CoinGecko"
    
    /// Detect format from CSV headers
    static func detect(from headers: [String]) -> CSVFormat {
        let normalizedHeaders = Set(headers.map { $0.lowercased().trimmingCharacters(in: .whitespaces) })
        
        // Coinbase format detection
        if normalizedHeaders.contains("timestamp") && normalizedHeaders.contains("transaction type") && normalizedHeaders.contains("asset") {
            return .coinbase
        }
        
        // Binance format detection
        if normalizedHeaders.contains("date(utc)") && normalizedHeaders.contains("pair") && normalizedHeaders.contains("side") {
            return .binance
        }
        
        // Kraken format detection
        if normalizedHeaders.contains("txid") && normalizedHeaders.contains("refid") && normalizedHeaders.contains("type") {
            return .kraken
        }
        
        // KuCoin format detection
        if normalizedHeaders.contains("tradecreateat") && normalizedHeaders.contains("symbol") && normalizedHeaders.contains("side") {
            return .kucoin
        }
        
        // Gemini format detection
        if normalizedHeaders.contains("date") && normalizedHeaders.contains("symbol") && normalizedHeaders.contains("type") && normalizedHeaders.contains("specification") {
            return .gemini
        }
        
        // CoinGecko portfolio export
        if normalizedHeaders.contains("coin") && normalizedHeaders.contains("amount") && normalizedHeaders.contains("purchase price") {
            return .coingecko
        }
        
        return .generic
    }
    
    /// Required columns for each format
    var requiredColumns: [String] {
        switch self {
        case .coinbase:
            return ["timestamp", "transaction type", "asset", "quantity transacted", "spot price at transaction"]
        case .binance:
            return ["date(utc)", "pair", "side", "price", "executed"]
        case .kraken:
            return ["time", "type", "asset", "amount", "fee"]
        case .kucoin:
            return ["tradecreateat", "symbol", "side", "price", "size"]
        case .gemini:
            return ["date", "symbol", "type", "amount", "price"]
        case .coingecko:
            return ["coin", "amount"]
        case .generic:
            return ["symbol", "quantity", "price", "date", "type"]
        }
    }
}

// MARK: - Import Result

struct CSVImportResult {
    let successCount: Int
    let failedCount: Int
    let transactions: [Transaction]
    let errors: [String]
    let detectedFormat: CSVFormat
}

// MARK: - CSV Import Service

final class CSVImportService {
    static let shared = CSVImportService()
    
    private init() {}
    
    // MARK: - Date Formatters
    
    private lazy var dateFormatters: [DateFormatter] = {
        let formats = [
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss",
            "MM/dd/yyyy HH:mm:ss",
            "MM/dd/yyyy",
            "dd/MM/yyyy HH:mm:ss",
            "dd/MM/yyyy",
            "yyyy-MM-dd",
            "MM-dd-yyyy",
            "dd-MM-yyyy"
        ]
        return formats.map { format in
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            return formatter
        }
    }()
    
    private func parseDate(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        for formatter in dateFormatters {
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        // Try ISO8601 as fallback
        if let date = ISO8601DateFormatter().date(from: trimmed) {
            return date
        }
        return nil
    }
    
    // MARK: - Import Methods
    
    /// Import transactions from a CSV file URL
    func importFromURL(_ url: URL) async throws -> CSVImportResult {
        guard url.startAccessingSecurityScopedResource() else {
            throw CSVImportError.fileNotFound
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw CSVImportError.invalidFormat
        }
        
        return try await importFromString(content)
    }
    
    /// Import transactions from CSV string content
    func importFromString(_ content: String) async throws -> CSVImportResult {
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        guard !lines.isEmpty else {
            throw CSVImportError.emptyFile
        }
        
        // Parse headers
        let headers = parseCSVLine(lines[0])
        let format = CSVFormat.detect(from: headers)
        
        // Validate required columns
        let normalizedHeaders = headers.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        let missingColumns = format.requiredColumns.filter { required in
            !normalizedHeaders.contains(required.lowercased())
        }
        
        // For generic format, check if we have minimum viable columns
        if format == .generic && missingColumns.count == format.requiredColumns.count {
            // Check for alternative column names
            let hasSymbol = normalizedHeaders.contains { $0.contains("symbol") || $0.contains("coin") || $0.contains("asset") || $0.contains("currency") }
            let hasAmount = normalizedHeaders.contains { $0.contains("amount") || $0.contains("quantity") || $0.contains("size") }
            
            if !hasSymbol || !hasAmount {
                throw CSVImportError.missingRequiredColumns(["symbol/coin", "amount/quantity"])
            }
        }
        
        // Parse data rows
        var transactions: [Transaction] = []
        var errors: [String] = []
        
        for (index, line) in lines.dropFirst().enumerated() {
            let rowNumber = index + 2 // 1-indexed, skip header
            
            do {
                let values = parseCSVLine(line)
                let headerMap = Dictionary(uniqueKeysWithValues: zip(normalizedHeaders, values))
                
                if let transaction = try parseTransaction(from: headerMap, format: format, row: rowNumber) {
                    transactions.append(transaction)
                }
            } catch {
                errors.append("Row \(rowNumber): \(error.localizedDescription)")
            }
        }
        
        return CSVImportResult(
            successCount: transactions.count,
            failedCount: errors.count,
            transactions: transactions,
            errors: errors,
            detectedFormat: format
        )
    }
    
    // MARK: - CSV Parsing
    
    /// Parse a CSV line handling quoted fields
    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var currentField = ""
        var inQuotes = false
        
        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(currentField.trimmingCharacters(in: .whitespaces))
                currentField = ""
            } else {
                currentField.append(char)
            }
        }
        
        // Add last field
        fields.append(currentField.trimmingCharacters(in: .whitespaces))
        
        return fields
    }
    
    // MARK: - Transaction Parsing
    
    private func parseTransaction(from headerMap: [String: String], format: CSVFormat, row: Int) throws -> Transaction? {
        switch format {
        case .coinbase:
            return try parseCoinbaseTransaction(from: headerMap, row: row)
        case .binance:
            return try parseBinanceTransaction(from: headerMap, row: row)
        case .kraken:
            return try parseKrakenTransaction(from: headerMap, row: row)
        case .kucoin:
            return try parseKuCoinTransaction(from: headerMap, row: row)
        case .gemini:
            return try parseGeminiTransaction(from: headerMap, row: row)
        case .coingecko:
            return try parseCoinGeckoTransaction(from: headerMap, row: row)
        case .generic:
            return try parseGenericTransaction(from: headerMap, row: row)
        }
    }
    
    // MARK: - Format-Specific Parsers
    
    private func parseCoinbaseTransaction(from map: [String: String], row: Int) throws -> Transaction? {
        guard let typeStr = map["transaction type"],
              let asset = map["asset"],
              let quantityStr = map["quantity transacted"],
              let priceStr = map["spot price at transaction"],
              let dateStr = map["timestamp"] else {
            return nil
        }
        
        // Skip non-buy/sell transactions
        let type = typeStr.lowercased()
        guard type == "buy" || type == "sell" else {
            return nil
        }
        
        guard let quantity = Double(quantityStr.replacingOccurrences(of: ",", with: "")),
              let price = Double(priceStr.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")),
              let date = parseDate(dateStr) else {
            throw CSVImportError.parsingFailed(row: row, reason: "Invalid number format")
        }
        
        return Transaction(
            coinSymbol: asset.uppercased(),
            quantity: abs(quantity),
            pricePerUnit: price,
            date: date,
            isBuy: type == "buy",
            isManual: false
        )
    }
    
    private func parseBinanceTransaction(from map: [String: String], row: Int) throws -> Transaction? {
        guard let pair = map["pair"],
              let sideStr = map["side"],
              let priceStr = map["price"],
              let executedStr = map["executed"],
              let dateStr = map["date(utc)"] else {
            return nil
        }
        
        // Extract base asset from pair (e.g., "BTCUSDT" -> "BTC")
        let baseAsset = extractBaseAsset(from: pair)
        
        guard let price = Double(priceStr.replacingOccurrences(of: ",", with: "")),
              let executed = Double(executedStr.components(separatedBy: " ").first?.replacingOccurrences(of: ",", with: "") ?? ""),
              let date = parseDate(dateStr) else {
            throw CSVImportError.parsingFailed(row: row, reason: "Invalid number format")
        }
        
        let isBuy = sideStr.lowercased() == "buy"
        
        return Transaction(
            coinSymbol: baseAsset.uppercased(),
            quantity: executed,
            pricePerUnit: price,
            date: date,
            isBuy: isBuy,
            isManual: false
        )
    }
    
    private func parseKrakenTransaction(from map: [String: String], row: Int) throws -> Transaction? {
        guard let typeStr = map["type"],
              let asset = map["asset"],
              let amountStr = map["amount"],
              let dateStr = map["time"] else {
            return nil
        }
        
        // Skip non-buy/sell types
        let type = typeStr.lowercased()
        guard type == "buy" || type == "sell" || type == "trade" else {
            return nil
        }
        
        guard let amount = Double(amountStr.replacingOccurrences(of: ",", with: "")),
              let date = parseDate(dateStr) else {
            throw CSVImportError.parsingFailed(row: row, reason: "Invalid number format")
        }
        
        let price = Double(map["price"]?.replacingOccurrences(of: ",", with: "") ?? "0") ?? 0
        let isBuy = amount > 0
        
        // Clean Kraken asset names (e.g., "XXBT" -> "BTC", "XETH" -> "ETH")
        let cleanedAsset = cleanKrakenAsset(asset)
        
        return Transaction(
            coinSymbol: cleanedAsset,
            quantity: abs(amount),
            pricePerUnit: price,
            date: date,
            isBuy: isBuy,
            isManual: false
        )
    }
    
    private func parseKuCoinTransaction(from map: [String: String], row: Int) throws -> Transaction? {
        guard let symbol = map["symbol"],
              let sideStr = map["side"],
              let priceStr = map["price"],
              let sizeStr = map["size"],
              let dateStr = map["tradecreateat"] else {
            return nil
        }
        
        let baseAsset = extractBaseAsset(from: symbol)
        
        guard let price = Double(priceStr.replacingOccurrences(of: ",", with: "")),
              let size = Double(sizeStr.replacingOccurrences(of: ",", with: "")),
              let date = parseDate(dateStr) else {
            throw CSVImportError.parsingFailed(row: row, reason: "Invalid number format")
        }
        
        let isBuy = sideStr.lowercased() == "buy"
        
        return Transaction(
            coinSymbol: baseAsset.uppercased(),
            quantity: size,
            pricePerUnit: price,
            date: date,
            isBuy: isBuy,
            isManual: false
        )
    }
    
    private func parseGeminiTransaction(from map: [String: String], row: Int) throws -> Transaction? {
        guard let symbol = map["symbol"],
              let typeStr = map["type"],
              let amountStr = map["amount"],
              let dateStr = map["date"] else {
            return nil
        }
        
        let type = typeStr.lowercased()
        guard type == "buy" || type == "sell" else {
            return nil
        }
        
        guard let amount = Double(amountStr.replacingOccurrences(of: ",", with: "")),
              let date = parseDate(dateStr) else {
            throw CSVImportError.parsingFailed(row: row, reason: "Invalid number format")
        }
        
        let price = Double(map["price"]?.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "") ?? "0") ?? 0
        let baseAsset = extractBaseAsset(from: symbol)
        
        return Transaction(
            coinSymbol: baseAsset.uppercased(),
            quantity: abs(amount),
            pricePerUnit: price,
            date: date,
            isBuy: type == "buy",
            isManual: false
        )
    }
    
    private func parseCoinGeckoTransaction(from map: [String: String], row: Int) throws -> Transaction? {
        guard let coin = map["coin"],
              let amountStr = map["amount"] else {
            return nil
        }
        
        guard let amount = Double(amountStr.replacingOccurrences(of: ",", with: "")) else {
            throw CSVImportError.parsingFailed(row: row, reason: "Invalid amount")
        }
        
        let price = Double(map["purchase price"]?.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "") ?? "0") ?? 0
        let dateStr = map["purchase date"] ?? map["date"]
        let date = dateStr.flatMap { parseDate($0) } ?? Date()
        
        return Transaction(
            coinSymbol: coin.uppercased(),
            quantity: abs(amount),
            pricePerUnit: price,
            date: date,
            isBuy: true,
            isManual: false
        )
    }
    
    private func parseGenericTransaction(from map: [String: String], row: Int) throws -> Transaction? {
        // Try various column name possibilities
        let symbol = map["symbol"] ?? map["coin"] ?? map["asset"] ?? map["currency"] ?? ""
        let quantityStr = map["quantity"] ?? map["amount"] ?? map["size"] ?? map["volume"] ?? ""
        let priceStr = map["price"] ?? map["rate"] ?? map["cost"] ?? "0"
        let dateStr = map["date"] ?? map["time"] ?? map["timestamp"] ?? ""
        let typeStr = map["type"] ?? map["side"] ?? map["action"] ?? "buy"
        
        guard !symbol.isEmpty, !quantityStr.isEmpty else {
            return nil
        }
        
        guard let quantity = Double(quantityStr.replacingOccurrences(of: ",", with: "")) else {
            throw CSVImportError.parsingFailed(row: row, reason: "Invalid quantity")
        }
        
        let price = Double(priceStr.replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")) ?? 0
        let date = dateStr.isEmpty ? Date() : (parseDate(dateStr) ?? Date())
        let isBuy = !typeStr.lowercased().contains("sell")
        
        return Transaction(
            coinSymbol: symbol.uppercased(),
            quantity: abs(quantity),
            pricePerUnit: price,
            date: date,
            isBuy: isBuy,
            isManual: false
        )
    }
    
    // MARK: - Helper Methods
    
    /// Extract base asset from trading pair (e.g., "BTCUSDT" -> "BTC")
    private func extractBaseAsset(from pair: String) -> String {
        let stablecoins = ["USDT", "USDC", "BUSD", "USD", "EUR", "GBP", "BTC", "ETH"]
        
        // Remove separator if present
        let cleanPair = pair.replacingOccurrences(of: "-", with: "").replacingOccurrences(of: "/", with: "").uppercased()
        
        for stable in stablecoins {
            if cleanPair.hasSuffix(stable) {
                return String(cleanPair.dropLast(stable.count))
            }
        }
        
        // If no quote found, return first 3-4 characters as base
        return String(cleanPair.prefix(cleanPair.count > 6 ? 3 : cleanPair.count))
    }
    
    /// Clean Kraken-specific asset names
    private func cleanKrakenAsset(_ asset: String) -> String {
        var clean = asset.uppercased()
        
        // Kraken prefixes
        if clean.hasPrefix("X") || clean.hasPrefix("Z") {
            clean = String(clean.dropFirst())
        }
        
        // Common mappings
        let mappings = [
            "XBT": "BTC",
            "XXBT": "BTC",
            "XETH": "ETH",
            "ZUSD": "USD",
            "ZEUR": "EUR"
        ]
        
        return mappings[asset.uppercased()] ?? clean
    }
    
    // MARK: - Supported File Types
    
    static var supportedTypes: [UTType] {
        [.commaSeparatedText, .plainText]
    }
}
