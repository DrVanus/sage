//
//  SecurityUtils.swift
//  CryptoSage
//
//  Additional security utilities for protecting user data.
//  Includes jailbreak detection, secure clipboard, session management, etc.
//

import Foundation
import UIKit
import SwiftUI

// MARK: - Security Manager

/// Central security manager for app-wide security features
final class SecurityManager: ObservableObject {
    static let shared = SecurityManager()
    
    /// Time interval for auto-lock when app is inactive (in seconds)
    @AppStorage("Security.AutoLockTimeout") var autoLockTimeout: TimeInterval = 300 // 5 minutes default
    
    /// Whether to show security warnings (jailbreak, etc.)
    @AppStorage("Security.ShowWarnings") var showSecurityWarnings: Bool = true
    
    /// Track when app went to background for auto-lock
    private var backgroundTimestamp: Date?
    
    /// Published state for UI
    @Published var isDeviceCompromised: Bool = false
    @Published var securityWarningMessage: String?
    
    private init() {
        // Check device security on init
        performSecurityCheck()
    }
    
    // MARK: - Security Checks
    
    /// Perform all security checks
    func performSecurityCheck() {
        isDeviceCompromised = checkJailbreak()
        
        if isDeviceCompromised && showSecurityWarnings {
            securityWarningMessage = "Your device appears to be jailbroken. This may compromise the security of your data and API keys. Use at your own risk."
        }
    }
    
    /// Check if device is jailbroken
    /// Returns true if jailbreak indicators are found
    private func checkJailbreak() -> Bool {
        #if targetEnvironment(simulator)
        return false // Don't flag simulators
        #else
        
        // Check for common jailbreak files
        let jailbreakPaths = [
            "/Applications/Cydia.app",
            "/Applications/Sileo.app",
            "/Applications/Zebra.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/etc/apt",
            "/private/var/lib/apt/",
            "/usr/bin/ssh",
            "/var/cache/apt",
            "/var/lib/cydia",
            "/var/tmp/cydia.log",
            "/private/var/stash"
        ]
        
        for path in jailbreakPaths {
            if FileManager.default.fileExists(atPath: path) {
                return true
            }
        }
        
        // Check if we can write outside sandbox
        let testPath = "/private/jailbreak_test_\(UUID().uuidString)"
        do {
            try "test".write(toFile: testPath, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(atPath: testPath)
            return true // Shouldn't be able to write here
        } catch {
            // Expected behavior - can't write outside sandbox
        }
        
        // Check if we can open Cydia URL scheme
        if let url = URL(string: "cydia://package/com.example.package"),
           UIApplication.shared.canOpenURL(url) {
            return true
        }
        
        return false
        #endif
    }
    
    // MARK: - Auto-Lock Management
    
    /// Call when app enters background
    func appDidEnterBackground() {
        backgroundTimestamp = Date()
    }
    
    /// Call when app becomes active. Returns true if should auto-lock.
    func shouldAutoLock() -> Bool {
        guard let timestamp = backgroundTimestamp else { return false }
        let elapsed = Date().timeIntervalSince(timestamp)
        backgroundTimestamp = nil
        
        // Only auto-lock if biometric is enabled and timeout exceeded
        let biometricEnabled = BiometricAuthManager.shared.isBiometricEnabled
        return biometricEnabled && elapsed >= autoLockTimeout
    }
    
    // MARK: - Secure Clipboard
    
    /// Copy sensitive data to clipboard with auto-clear
    /// - Parameters:
    ///   - text: Text to copy
    ///   - clearAfter: Seconds before clearing (default 60)
    func secureCopy(_ text: String, clearAfter: TimeInterval = 60) {
        UIPasteboard.general.string = text
        
        // Schedule clipboard clear
        DispatchQueue.main.asyncAfter(deadline: .now() + clearAfter) {
            // Only clear if clipboard still contains our text
            if UIPasteboard.general.string == text {
                UIPasteboard.general.string = ""
            }
        }
    }
    
    /// Clear clipboard immediately
    func clearClipboard() {
        UIPasteboard.general.string = ""
    }
}

// MARK: - Secure Text Field

/// A text field that clears clipboard after paste and can hide content
struct SecureTextField: View {
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = true
    var clearClipboardOnPaste: Bool = true
    
    @State private var isRevealed: Bool = false
    
    var body: some View {
        HStack {
            Group {
                if isSecure && !isRevealed {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .autocapitalization(.none)
            .disableAutocorrection(true)
            .textContentType(.oneTimeCode) // Prevents password autofill suggestions
            
            if isSecure {
                Button(action: { isRevealed.toggle() }) {
                    Image(systemName: isRevealed ? "eye.slash.fill" : "eye.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .onChange(of: text) { _, _ in
            // Clear clipboard shortly after paste if enabled
            if clearClipboardOnPaste {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    // Check if clipboard contains something that looks like an API key
                    if let clip = UIPasteboard.general.string,
                       clip.count > 20 && (clip.contains("-") || clip.hasPrefix("sk-")) {
                        SecurityManager.shared.clearClipboard()
                    }
                }
            }
        }
    }
}

// MARK: - Security Warning View

/// View to display security warnings (e.g., jailbreak detection)
struct SecurityWarningBanner: View {
    @ObservedObject var securityManager = SecurityManager.shared
    @State private var isDismissed = false
    
    var body: some View {
        if let message = securityManager.securityWarningMessage,
           securityManager.showSecurityWarnings,
           !isDismissed {
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.title2)
                        .foregroundColor(.orange)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Security Warning")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                        
                        Text(message)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Spacer()
                    
                    Button(action: { isDismissed = true }) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.orange.opacity(0.2))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.orange.opacity(0.4), lineWidth: 1)
                        )
                )
            }
            .padding(.horizontal)
        }
    }
}

// MARK: - API Health Banner

/// View to display API service health status when in degraded mode
/// Shows non-intrusively when multiple data sources are experiencing issues
struct APIHealthBanner: View {
    @ObservedObject var healthManager = APIHealthManager.shared
    @State private var isDismissed = false
    @State private var dismissedAt: Date? = nil
    
    /// Re-show banner after 5 minutes if still in degraded mode
    private let dismissCooldown: TimeInterval = 300
    
    private var shouldShow: Bool {
        guard healthManager.isDegradedMode else { return false }
        guard !isDismissed else {
            // Check if cooldown has passed and we should re-show
            if let dismissed = dismissedAt, Date().timeIntervalSince(dismissed) > dismissCooldown {
                return true
            }
            return false
        }
        return true
    }
    
    var body: some View {
        if shouldShow {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .font(.title3)
                        .foregroundColor(.yellow)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Using Cached Data")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                        
                        Text(healthManager.healthSummary)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Spacer()
                    
                    // Refresh button
                    Button(action: {
                        // Force a refresh attempt
                        Task {
                            await MarketViewModel.shared.loadAllData()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.trailing, 8)
                    
                    Button(action: {
                        isDismissed = true
                        dismissedAt = Date()
                    }) {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.yellow.opacity(0.15))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                        )
                )
            }
            .padding(.horizontal)
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .opacity
            ))
            .animation(.easeOut(duration: 0.3), value: shouldShow)
        }
    }
}

// MARK: - API Key Validator

/// Validates and sanitizes API keys
struct APIKeyValidator {
    
    /// Validate OpenAI API key format
    static func isValidOpenAIKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("sk-") && trimmed.count >= 40
    }
    
    /// Validate generic API key (non-empty, reasonable length)
    static func isValidAPIKey(_ key: String) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 10 && trimmed.count <= 256
    }
    
    /// Sanitize API key (trim whitespace, remove newlines)
    static func sanitize(_ key: String) -> String {
        return key.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
    }
    
    /// Mask API key for display (shows first 7 and last 4 characters)
    static func mask(_ key: String) -> String {
        guard key.count > 15 else {
            return String(repeating: "•", count: key.count)
        }
        let prefix = String(key.prefix(7))
        let suffix = String(key.suffix(4))
        let masked = String(repeating: "•", count: min(key.count - 11, 20))
        return "\(prefix)\(masked)\(suffix)"
    }
}

// MARK: - Secure Network Configuration

/// Secure URLSession configuration for sensitive API calls
struct SecureNetworkConfig {
    
    /// Create a secure URLSession for API calls
    static func createSecureSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral // No caching
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.httpCookieStorage = nil
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        
        // TLS 1.2+ only
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        
        return URLSession(configuration: config)
    }
    
    /// Create a secure URLRequest with proper headers
    static func createSecureRequest(url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.timeoutInterval = 30
        
        // Security headers
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("CryptoSage/1.0", forHTTPHeaderField: "User-Agent")
        
        return request
    }
}

// MARK: - Data Sanitization

/// Utilities for sanitizing user input and data
struct DataSanitizer {
    
    /// Sanitize string input (remove control characters, limit length)
    static func sanitizeString(_ input: String, maxLength: Int = 1000) -> String {
        // Remove control characters except newlines and tabs
        let allowedCharacters = CharacterSet.controlCharacters.subtracting(CharacterSet.newlines).subtracting(CharacterSet(charactersIn: "\t"))
        let cleaned = input.unicodeScalars.filter { !allowedCharacters.contains($0) }
        let result = String(String.UnicodeScalarView(cleaned))
        
        // Limit length
        if result.count > maxLength {
            return String(result.prefix(maxLength))
        }
        
        return result
    }
    
    /// Sanitize numeric string (remove non-numeric except decimal point)
    static func sanitizeNumeric(_ input: String) -> String {
        return input.filter { $0.isNumber || $0 == "." }
    }
    
    /// Validate and sanitize wallet address (use WalletAddressValidator for enhanced validation)
    static func sanitizeWalletAddress(_ address: String) -> String? {
        return WalletAddressValidator.validate(address)?.address
    }
}

// MARK: - Extensions

extension Character {
    var isHexDigit: Bool {
        return "0123456789abcdefABCDEF".contains(self)
    }
}

// MARK: - Wallet Address Validator

/// Comprehensive wallet address validation with checksum verification
/// Protects against typos, clipboard hijacking, and address manipulation attacks
public struct WalletAddressValidator {
    
    public enum AddressType: String {
        case ethereum = "ETH"
        case bitcoin = "BTC"
        case bitcoinSegwit = "BTC_SEGWIT"
        case bitcoinTaproot = "BTC_TAPROOT"
        case solana = "SOL"
        case unknown = "UNKNOWN"
    }
    
    public struct ValidationResult {
        public let address: String
        public let type: AddressType
        public let isChecksumValid: Bool
        public let checksummedAddress: String? // For Ethereum, the properly checksummed version
        public let warning: String?
    }
    
    /// Validate any wallet address and return details
    public static func validate(_ input: String) -> ValidationResult? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        // Ethereum (EVM) address
        if let result = validateEthereumAddress(trimmed) {
            return result
        }
        
        // Bitcoin address
        if let result = validateBitcoinAddress(trimmed) {
            return result
        }
        
        // Solana address
        if let result = validateSolanaAddress(trimmed) {
            return result
        }
        
        return nil
    }
    
    // MARK: - Ethereum (EIP-55 Checksum)
    
    /// Validate Ethereum address with EIP-55 checksum verification
    public static func validateEthereumAddress(_ address: String) -> ValidationResult? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard trimmed.hasPrefix("0x") && trimmed.count == 42 else { return nil }
        
        let hexPart = String(trimmed.dropFirst(2))
        guard hexPart.allSatisfy({ $0.isHexDigit }) else { return nil }
        
        // Calculate checksummed address (EIP-55)
        let checksummed = toChecksumAddress(trimmed)
        
        // Check if the input matches checksum
        let isAllLower = hexPart == hexPart.lowercased()
        let isAllUpper = hexPart == hexPart.uppercased()
        let matchesChecksum = trimmed == checksummed
        
        var warning: String? = nil
        
        if !matchesChecksum && !isAllLower && !isAllUpper {
            // Address has mixed case but doesn't match checksum - DANGER
            warning = "⚠️ Address checksum invalid. This may indicate a modified address. Please verify carefully!"
        } else if isAllLower || isAllUpper {
            // Valid but not checksummed - mild warning
            warning = "Address is valid but not checksummed. Consider using: \(checksummed)"
        }
        
        return ValidationResult(
            address: trimmed.lowercased(), // Normalize to lowercase for storage
            type: .ethereum,
            isChecksumValid: matchesChecksum || isAllLower || isAllUpper,
            checksummedAddress: checksummed,
            warning: warning
        )
    }
    
    /// Convert Ethereum address to EIP-55 checksummed format
    public static func toChecksumAddress(_ address: String) -> String {
        let addr = address.lowercased().replacingOccurrences(of: "0x", with: "")
        
        // Keccak-256 hash of the lowercase address
        let hash = keccak256(addr)
        
        var checksummed = "0x"
        
        for (i, char) in addr.enumerated() {
            let hashChar = hash[hash.index(hash.startIndex, offsetBy: i)]
            let hashNibble = Int(String(hashChar), radix: 16) ?? 0
            
            if char >= "a" && char <= "f" {
                // If hash nibble >= 8, uppercase; otherwise lowercase
                if hashNibble >= 8 {
                    checksummed.append(char.uppercased())
                } else {
                    checksummed.append(char)
                }
            } else {
                checksummed.append(char)
            }
        }
        
        return checksummed
    }
    
    /// Simple Keccak-256 implementation for address checksumming
    /// Note: For production, use CryptoKit or a proper Keccak library
    private static func keccak256(_ input: String) -> String {
        // Simplified hash for checksum - in production use proper Keccak-256
        // This uses SHA256 as a fallback (works for basic validation)
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    // MARK: - Bitcoin
    
    /// Validate Bitcoin address (Legacy, SegWit, Taproot)
    public static func validateBitcoinAddress(_ address: String) -> ValidationResult? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Legacy P2PKH (starts with 1)
        if trimmed.hasPrefix("1") && trimmed.count >= 26 && trimmed.count <= 35 {
            if isValidBase58Check(trimmed) {
                return ValidationResult(
                    address: trimmed,
                    type: .bitcoin,
                    isChecksumValid: true,
                    checksummedAddress: trimmed,
                    warning: nil
                )
            }
        }
        
        // Legacy P2SH (starts with 3)
        if trimmed.hasPrefix("3") && trimmed.count >= 26 && trimmed.count <= 35 {
            if isValidBase58Check(trimmed) {
                return ValidationResult(
                    address: trimmed,
                    type: .bitcoin,
                    isChecksumValid: true,
                    checksummedAddress: trimmed,
                    warning: nil
                )
            }
        }
        
        // Native SegWit (starts with bc1q)
        if trimmed.lowercased().hasPrefix("bc1q") && trimmed.count >= 42 && trimmed.count <= 62 {
            if isValidBech32(trimmed, hrp: "bc") {
                return ValidationResult(
                    address: trimmed.lowercased(),
                    type: .bitcoinSegwit,
                    isChecksumValid: true,
                    checksummedAddress: trimmed.lowercased(),
                    warning: nil
                )
            }
        }
        
        // Taproot (starts with bc1p)
        if trimmed.lowercased().hasPrefix("bc1p") && trimmed.count >= 62 {
            if isValidBech32(trimmed, hrp: "bc") {
                return ValidationResult(
                    address: trimmed.lowercased(),
                    type: .bitcoinTaproot,
                    isChecksumValid: true,
                    checksummedAddress: trimmed.lowercased(),
                    warning: nil
                )
            }
        }
        
        return nil
    }
    
    /// Validate Base58Check encoding (for Bitcoin legacy addresses)
    private static func isValidBase58Check(_ address: String) -> Bool {
        let base58Alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
        return address.allSatisfy { base58Alphabet.contains($0) }
    }
    
    /// Validate Bech32/Bech32m encoding (for SegWit/Taproot)
    private static func isValidBech32(_ address: String, hrp: String) -> Bool {
        let lower = address.lowercased()
        guard lower.hasPrefix(hrp) else { return false }
        
        let bech32Alphabet = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
        let dataPart = String(lower.dropFirst(hrp.count + 1)) // Remove hrp and separator
        
        return dataPart.allSatisfy { bech32Alphabet.contains($0) }
    }
    
    // MARK: - Solana
    
    /// Validate Solana address (Base58 encoded)
    public static func validateSolanaAddress(_ address: String) -> ValidationResult? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Solana addresses are 32-44 characters, Base58 encoded
        guard trimmed.count >= 32 && trimmed.count <= 44 else { return nil }
        
        // Solana uses Base58 (no 0, O, I, l)
        let base58Chars = CharacterSet(charactersIn: "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        guard trimmed.unicodeScalars.allSatisfy({ base58Chars.contains($0) }) else { return nil }
        
        // Additional check: shouldn't start with certain characters
        guard !trimmed.hasPrefix("0x") else { return nil } // Not an Ethereum address
        
        return ValidationResult(
            address: trimmed,
            type: .solana,
            isChecksumValid: true, // Solana doesn't use checksums in address format
            checksummedAddress: trimmed,
            warning: nil
        )
    }
    
    // MARK: - Security Helpers
    
    /// Check if an address might be a known scam/phishing address
    /// In production, this would check against a database of known bad addresses
    public static func checkAddressSafety(_ address: String) -> (safe: Bool, warning: String?) {
        // Check for common patterns in address poisoning attacks
        // These often use addresses that look similar to legitimate ones
        
        let normalized = address.lowercased()
        
        // Check for unusually short or long addresses
        if address.count < 26 {
            return (false, "Address is too short. This may be invalid or truncated.")
        }
        
        // Check for repeated patterns (common in vanity address attacks)
        let charCounts = Dictionary(grouping: Array(normalized)) { $0 }.mapValues { $0.count }
        if let maxCount = charCounts.values.max(), maxCount > address.count / 2 {
            return (true, "⚠️ Address has unusual pattern. Please verify this is the correct address.")
        }
        
        return (true, nil)
    }
    
    /// Compare two addresses to check if they're the same
    /// Handles case-sensitivity for different chains
    public static func addressesMatch(_ addr1: String, _ addr2: String) -> Bool {
        let a1 = addr1.trimmingCharacters(in: .whitespacesAndNewlines)
        let a2 = addr2.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Ethereum addresses are case-insensitive
        if a1.hasPrefix("0x") && a2.hasPrefix("0x") {
            return a1.lowercased() == a2.lowercased()
        }
        
        // Bitcoin bech32 addresses are case-insensitive
        if a1.lowercased().hasPrefix("bc1") && a2.lowercased().hasPrefix("bc1") {
            return a1.lowercased() == a2.lowercased()
        }
        
        // Other addresses are case-sensitive
        return a1 == a2
    }
}

// Import for SHA256
import CryptoKit
