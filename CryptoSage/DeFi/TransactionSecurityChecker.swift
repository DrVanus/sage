//
//  TransactionSecurityChecker.swift
//  CryptoSage
//
//  Security checks for DeFi transactions to protect users from scams and mistakes.
//  Implements checks similar to what MetaMask and other wallets do.
//

import Foundation
import SwiftUI

// MARK: - Transaction Security Checker

/// Analyzes DeFi transactions for potential security risks
public final class TransactionSecurityChecker {
    public static let shared = TransactionSecurityChecker()
    
    private init() {}
    
    // MARK: - Risk Levels
    
    public enum RiskLevel: Int, Comparable {
        case safe = 0
        case low = 1
        case medium = 2
        case high = 3
        case critical = 4
        
        public static func < (lhs: RiskLevel, rhs: RiskLevel) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
        
        public var color: Color {
            switch self {
            case .safe: return .green
            case .low: return .blue
            case .medium: return .yellow
            case .high: return .orange
            case .critical: return .red
            }
        }
        
        public var icon: String {
            switch self {
            case .safe: return "checkmark.shield.fill"
            case .low: return "info.circle.fill"
            case .medium: return "exclamationmark.triangle.fill"
            case .high: return "exclamationmark.octagon.fill"
            case .critical: return "xmark.octagon.fill"
            }
        }
    }
    
    // MARK: - Security Check Result
    
    public struct SecurityCheckResult {
        public let overallRisk: RiskLevel
        public let warnings: [SecurityWarning]
        public let recommendations: [String]
        public let shouldProceed: Bool
        
        public init(
            overallRisk: RiskLevel,
            warnings: [SecurityWarning],
            recommendations: [String] = [],
            shouldProceed: Bool = true
        ) {
            self.overallRisk = overallRisk
            self.warnings = warnings
            self.recommendations = recommendations
            self.shouldProceed = shouldProceed
        }
        
        public static let safe = SecurityCheckResult(
            overallRisk: .safe,
            warnings: [],
            recommendations: [],
            shouldProceed: true
        )
    }
    
    public struct SecurityWarning: Identifiable {
        public let id = UUID()
        public let level: RiskLevel
        public let title: String
        public let message: String
        public let details: String?
        
        public init(level: RiskLevel, title: String, message: String, details: String? = nil) {
            self.level = level
            self.title = title
            self.message = message
            self.details = details
        }
    }
    
    // MARK: - Transaction Analysis
    
    /// Analyze a transaction for security risks
    public func analyzeTransaction(
        from: String,
        to: String,
        value: String?,
        data: String?,
        chainId: Int
    ) -> SecurityCheckResult {
        var warnings: [SecurityWarning] = []
        var recommendations: [String] = []
        var maxRisk: RiskLevel = .safe
        
        // 1. Check destination address
        let addressCheck = checkDestinationAddress(to, chainId: chainId)
        warnings.append(contentsOf: addressCheck.warnings)
        if addressCheck.risk > maxRisk { maxRisk = addressCheck.risk }
        
        // 2. Check if sending to self
        if WalletAddressValidator.addressesMatch(from, to) {
            warnings.append(SecurityWarning(
                level: .medium,
                title: "Sending to yourself",
                message: "You're sending tokens to your own address. This will just waste gas fees."
            ))
            if maxRisk < .medium { maxRisk = .medium }
        }
        
        // 3. Check transaction data (contract interaction)
        if let data = data, !data.isEmpty, data != "0x" {
            let dataCheck = checkContractData(data)
            warnings.append(contentsOf: dataCheck.warnings)
            if dataCheck.risk > maxRisk { maxRisk = dataCheck.risk }
        }
        
        // 4. Check value (if sending ETH)
        if let value = value, !value.isEmpty {
            let valueCheck = checkTransactionValue(value, chainId: chainId)
            warnings.append(contentsOf: valueCheck.warnings)
            if valueCheck.risk > maxRisk { maxRisk = valueCheck.risk }
        }
        
        // Add general recommendations
        if maxRisk >= .medium {
            recommendations.append("Double-check all transaction details before confirming")
            recommendations.append("Verify the contract address on a block explorer")
        }
        
        if maxRisk >= .high {
            recommendations.append("Consider using a hardware wallet for extra security")
            recommendations.append("Start with a small test transaction")
        }
        
        return SecurityCheckResult(
            overallRisk: maxRisk,
            warnings: warnings,
            recommendations: recommendations,
            shouldProceed: maxRisk < .critical
        )
    }
    
    // MARK: - Address Checks
    
    private func checkDestinationAddress(_ address: String, chainId: Int) -> (risk: RiskLevel, warnings: [SecurityWarning]) {
        var warnings: [SecurityWarning] = []
        var risk: RiskLevel = .safe
        
        // Validate address format
        guard let validation = WalletAddressValidator.validate(address) else {
            return (.critical, [SecurityWarning(
                level: .critical,
                title: "Invalid address",
                message: "The destination address is not valid. Do not proceed."
            )])
        }
        
        // Check for checksum issues (Ethereum)
        if validation.type == .ethereum {
            if !validation.isChecksumValid {
                warnings.append(SecurityWarning(
                    level: .high,
                    title: "Checksum mismatch",
                    message: "The address checksum doesn't match. This could indicate the address was modified.",
                    details: "Expected: \(validation.checksummedAddress ?? address)"
                ))
                risk = .high
            }
        }
        
        // Check for known contract vs EOA
        // In production, you'd check this on-chain
        if isLikelyContractAddress(address, chainId: chainId) {
            warnings.append(SecurityWarning(
                level: .low,
                title: "Contract interaction",
                message: "You're interacting with a smart contract. Make sure you trust this contract."
            ))
            if risk < .low { risk = .low }
        }
        
        // Check address safety
        let safetyCheck = WalletAddressValidator.checkAddressSafety(address)
        if let warning = safetyCheck.warning {
            warnings.append(SecurityWarning(
                level: .medium,
                title: "Address pattern warning",
                message: warning
            ))
            if risk < .medium { risk = .medium }
        }
        
        return (risk, warnings)
    }
    
    // MARK: - Contract Data Checks
    
    private func checkContractData(_ data: String) -> (risk: RiskLevel, warnings: [SecurityWarning]) {
        var warnings: [SecurityWarning] = []
        var risk: RiskLevel = .low // Contract interactions are inherently more risky
        
        // Check for known dangerous function selectors
        let functionSelector = String(data.prefix(10))
        
        // Known risky function selectors
        let dangerousFunctions: [String: (name: String, risk: RiskLevel, message: String)] = [
            "0x095ea7b3": ("approve", .high, "This grants unlimited token spending approval. Consider using increaseAllowance instead."),
            "0xa22cb465": ("setApprovalForAll", .critical, "This grants approval for ALL your NFTs. Only do this with trusted contracts."),
            "0x42842e0e": ("safeTransferFrom", .medium, "Transferring an NFT. Verify the recipient address."),
            "0x23b872dd": ("transferFrom", .medium, "Transferring tokens on someone's behalf."),
        ]
        
        if let dangerous = dangerousFunctions[functionSelector.lowercased()] {
            warnings.append(SecurityWarning(
                level: dangerous.risk,
                title: "\(dangerous.name) function detected",
                message: dangerous.message
            ))
            if dangerous.risk > risk { risk = dangerous.risk }
            
            // Special check for unlimited approvals
            if functionSelector.lowercased() == "0x095ea7b3" {
                // Check if amount is max uint256 (unlimited)
                if data.count >= 74 {
                    let amountHex = String(data.suffix(64))
                    if amountHex == "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" {
                        warnings.append(SecurityWarning(
                            level: .high,
                            title: "Unlimited approval requested",
                            message: "This contract is requesting unlimited access to spend your tokens. Consider approving only the amount needed."
                        ))
                    }
                }
            }
        }
        
        // Check for suspiciously long data
        if data.count > 1000 {
            warnings.append(SecurityWarning(
                level: .medium,
                title: "Complex transaction",
                message: "This transaction contains a lot of data. Make sure you understand what it does."
            ))
        }
        
        return (risk, warnings)
    }
    
    // MARK: - Value Checks
    
    private func checkTransactionValue(_ value: String, chainId: Int) -> (risk: RiskLevel, warnings: [SecurityWarning]) {
        var warnings: [SecurityWarning] = []
        var risk: RiskLevel = .safe
        
        // Convert hex value to decimal
        let cleanValue = value.hasPrefix("0x") ? String(value.dropFirst(2)) : value
        guard let valueWei = UInt64(cleanValue, radix: 16) else {
            return (.safe, [])
        }
        
        // Convert to ETH (or native token)
        let valueEth = Double(valueWei) / 1e18
        
        // Check for large transfers
        if valueEth > 1.0 {
            warnings.append(SecurityWarning(
                level: .medium,
                title: "Large transfer",
                message: String(format: "Sending %.4f ETH. Please verify this is correct.", valueEth)
            ))
            if risk < .medium { risk = .medium }
        }
        
        if valueEth > 10.0 {
            warnings.append(SecurityWarning(
                level: .high,
                title: "Very large transfer",
                message: String(format: "Sending %.4f ETH (> 10 ETH). Please double-check everything.", valueEth)
            ))
            risk = .high
        }
        
        return (risk, warnings)
    }
    
    // MARK: - Helpers
    
    /// Check if an address is likely a contract (heuristic)
    private func isLikelyContractAddress(_ address: String, chainId: Int) -> Bool {
        // Known protocol contracts (could expand this list)
        let knownContracts = [
            "0x7a250d5630b4cf539739df2c5dacb4c659f2488d", // Uniswap V2 Router
            "0xe592427a0aece92de3edee1f18e0157c05861564", // Uniswap V3 Router
            "0x68b3465833fb72a70ecdf485e0e4c7bd8665fc45", // Uniswap Universal Router
            "0x1111111254eeb25477b68fb85ed929f73a960582", // 1inch Router
            "0x87870bca3f3fd6335c3f4ce8392d69350b4fa4e2", // Aave V3 Pool
            "0xae7ab96520de3a18e5e111b5eaab095312d7fe84", // Lido stETH
        ]
        
        return knownContracts.contains(address.lowercased())
    }
    
    // MARK: - Token Approval Checks
    
    /// Analyze a token approval transaction
    public func analyzeApproval(
        token: String,
        spender: String,
        amount: String,
        chainId: Int
    ) -> SecurityCheckResult {
        var warnings: [SecurityWarning] = []
        var risk: RiskLevel = .medium // Approvals are inherently risky
        
        // Check if unlimited approval
        if amount.lowercased() == "unlimited" || 
           amount == "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" ||
           amount == "115792089237316195423570985008687907853269984665640564039457584007913129639935" {
            warnings.append(SecurityWarning(
                level: .high,
                title: "Unlimited approval",
                message: "You're approving unlimited access to your tokens. The spender can transfer any amount at any time.",
                details: "Consider approving only the amount you need for this transaction."
            ))
            risk = .high
        }
        
        // Check spender address
        let spenderCheck = checkDestinationAddress(spender, chainId: chainId)
        warnings.append(contentsOf: spenderCheck.warnings)
        
        // Add recommendations
        let recommendations = [
            "Review the spender contract on Etherscan",
            "Consider using revoke.cash to manage approvals",
            "Set a specific amount instead of unlimited if possible"
        ]
        
        return SecurityCheckResult(
            overallRisk: risk,
            warnings: warnings,
            recommendations: recommendations,
            shouldProceed: risk < .critical
        )
    }
}

// MARK: - Transaction Warning View

/// SwiftUI view for displaying transaction warnings
public struct TransactionWarningView: View {
    let result: TransactionSecurityChecker.SecurityCheckResult
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    public init(
        result: TransactionSecurityChecker.SecurityCheckResult,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.result = result
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: result.overallRisk.icon)
                    .font(.title)
                    .foregroundColor(result.overallRisk.color)
                
                Text(headerTitle)
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            .padding(.top)
            
            // Warnings
            if !result.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(result.warnings) { warning in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: warning.level.icon)
                                .foregroundColor(warning.level.color)
                                .frame(width: 20)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(warning.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.primary)
                                
                                Text(warning.message)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                if let details = warning.details {
                                    Text(details)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .padding(.top, 2)
                                }
                            }
                        }
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(12)
            }
            
            // Recommendations
            if !result.recommendations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recommendations")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                    
                    ForEach(result.recommendations, id: \.self) { rec in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                            Text(rec)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
            }
            
            // Actions
            HStack(spacing: 12) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.secondary.opacity(0.2))
                        .cornerRadius(12)
                }
                
                if result.shouldProceed {
                    Button(action: onConfirm) {
                        Text("Confirm")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(result.overallRisk.color)
                            .cornerRadius(12)
                    }
                }
            }
            .padding()
        }
        .padding()
        .background(Color(UIColor.systemBackground))
        .cornerRadius(20)
    }
    
    private var headerTitle: String {
        switch result.overallRisk {
        case .safe: return "Transaction looks safe"
        case .low: return "Minor concerns"
        case .medium: return "Review carefully"
        case .high: return "Significant risks detected"
        case .critical: return "Transaction blocked"
        }
    }
}
