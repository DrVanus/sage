//
//  PINAuthManager.swift
//  CryptoSage
//
//  PIN code authentication as backup for biometrics.
//  Implements rate limiting and secure PIN storage like Coinbase/Binance.
//

import Foundation
import CryptoKit
import SwiftUI

// MARK: - PIN Auth Manager

/// Manages PIN code authentication with secure storage and rate limiting
final class PINAuthManager: ObservableObject {
    static let shared = PINAuthManager()
    
    // MARK: - Constants
    
    private let keychainService = "CryptoSage.PIN"
    private let pinHashAccount = "pin_hash"
    private let pinSaltAccount = "pin_salt"
    private let failedAttemptsKey = "PINAuth.FailedAttempts"
    private let lockoutEndKey = "PINAuth.LockoutEnd"
    
    /// PIN length requirement
    let requiredPINLength = 6
    
    /// Maximum failed attempts before lockout
    let maxFailedAttempts = 5
    
    /// Lockout duration in seconds (5 minutes)
    let lockoutDuration: TimeInterval = 300
    
    // MARK: - Published State
    
    @Published private(set) var isPINSet: Bool = false
    @Published private(set) var failedAttempts: Int = 0
    @Published private(set) var isLockedOut: Bool = false
    @Published private(set) var lockoutRemainingSeconds: Int = 0
    
    // MARK: - Private State
    
    private var lockoutTimer: Timer?
    
    private init() {
        loadState()
        checkLockoutStatus()
    }
    
    // MARK: - State Management
    
    private func loadState() {
        // Check if PIN is set
        isPINSet = (try? KeychainHelper.shared.read(service: keychainService, account: pinHashAccount)) != nil
        
        // Load failed attempts
        failedAttempts = UserDefaults.standard.integer(forKey: failedAttemptsKey)
    }
    
    private func checkLockoutStatus() {
        let lockoutEnd = UserDefaults.standard.double(forKey: lockoutEndKey)
        
        if lockoutEnd > 0 {
            let remaining = lockoutEnd - Date().timeIntervalSince1970
            
            if remaining > 0 {
                isLockedOut = true
                lockoutRemainingSeconds = Int(remaining)
                startLockoutTimer()
            } else {
                // Lockout expired
                clearLockout()
            }
        }
    }
    
    // MARK: - PIN Setup
    
    /// Set up a new PIN
    /// - Parameter pin: The 6-digit PIN to set
    /// - Returns: True if PIN was set successfully
    @discardableResult
    func setPIN(_ pin: String) -> Bool {
        guard pin.count == requiredPINLength,
              pin.allSatisfy({ $0.isNumber }) else {
            print("❌ [PINAuth] Invalid PIN format")
            return false
        }
        
        // Generate a random salt
        var saltBytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes)
        let salt = Data(saltBytes).base64EncodedString()
        
        // Hash the PIN with salt using SHA-256
        let pinWithSalt = pin + salt
        let hash = SHA256.hash(data: Data(pinWithSalt.utf8))
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        
        do {
            // Store hash and salt in Keychain
            try KeychainHelper.shared.save(hashString, service: keychainService, account: pinHashAccount)
            try KeychainHelper.shared.save(salt, service: keychainService, account: pinSaltAccount)
            
            isPINSet = true
            resetFailedAttempts()
            
            print("✅ [PINAuth] PIN set successfully")
            return true
        } catch {
            print("❌ [PINAuth] Failed to save PIN: \(error)")
            return false
        }
    }
    
    /// Change the PIN (requires current PIN verification)
    /// - Parameters:
    ///   - currentPIN: The current PIN for verification
    ///   - newPIN: The new PIN to set
    /// - Returns: True if PIN was changed successfully
    func changePIN(currentPIN: String, newPIN: String) -> Bool {
        guard verifyPIN(currentPIN) else {
            return false
        }
        
        // Remove old PIN and set new one
        removePIN()
        return setPIN(newPIN)
    }
    
    /// Remove the PIN
    func removePIN() {
        try? KeychainHelper.shared.delete(service: keychainService, account: pinHashAccount)
        try? KeychainHelper.shared.delete(service: keychainService, account: pinSaltAccount)
        isPINSet = false
        resetFailedAttempts()
        print("🗑️ [PINAuth] PIN removed")
    }
    
    // MARK: - PIN Verification
    
    /// Verify a PIN
    /// - Parameter pin: The PIN to verify
    /// - Returns: True if PIN is correct
    func verifyPIN(_ pin: String) -> Bool {
        // Check lockout
        guard !isLockedOut else {
            print("🔒 [PINAuth] Account locked out")
            return false
        }
        
        guard let storedHash = try? KeychainHelper.shared.read(service: keychainService, account: pinHashAccount),
              let salt = try? KeychainHelper.shared.read(service: keychainService, account: pinSaltAccount) else {
            print("❌ [PINAuth] No PIN configured")
            return false
        }
        
        // Hash the provided PIN with stored salt
        let pinWithSalt = pin + salt
        let hash = SHA256.hash(data: Data(pinWithSalt.utf8))
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        
        // Compare hashes
        if hashString == storedHash {
            resetFailedAttempts()
            print("✅ [PINAuth] PIN verified")
            return true
        } else {
            recordFailedAttempt()
            print("❌ [PINAuth] Invalid PIN (Attempt \(failedAttempts)/\(maxFailedAttempts))")
            return false
        }
    }
    
    // MARK: - Rate Limiting
    
    private func recordFailedAttempt() {
        failedAttempts += 1
        UserDefaults.standard.set(failedAttempts, forKey: failedAttemptsKey)
        
        if failedAttempts >= maxFailedAttempts {
            startLockout()
        }
    }
    
    private func resetFailedAttempts() {
        failedAttempts = 0
        UserDefaults.standard.set(0, forKey: failedAttemptsKey)
        clearLockout()
    }
    
    private func startLockout() {
        isLockedOut = true
        let lockoutEnd = Date().timeIntervalSince1970 + lockoutDuration
        UserDefaults.standard.set(lockoutEnd, forKey: lockoutEndKey)
        lockoutRemainingSeconds = Int(lockoutDuration)
        
        startLockoutTimer()
        
        print("🔒 [PINAuth] Account locked for \(Int(lockoutDuration)) seconds")
    }
    
    private func clearLockout() {
        isLockedOut = false
        lockoutRemainingSeconds = 0
        UserDefaults.standard.removeObject(forKey: lockoutEndKey)
        lockoutTimer?.invalidate()
        lockoutTimer = nil
    }
    
    private func startLockoutTimer() {
        lockoutTimer?.invalidate()
        lockoutTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            if self.lockoutRemainingSeconds > 0 {
                self.lockoutRemainingSeconds -= 1
            } else {
                self.clearLockout()
                self.resetFailedAttempts()
            }
        }
    }
    
    // MARK: - Formatted Time
    
    /// Formatted lockout remaining time (e.g., "4:32")
    var formattedLockoutTime: String {
        let minutes = lockoutRemainingSeconds / 60
        let seconds = lockoutRemainingSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - PIN Entry View

/// SwiftUI view for PIN entry with keypad
struct PINEntryView: View {
    @ObservedObject private var pinManager = PINAuthManager.shared
    
    let mode: PINMode
    let onComplete: (Bool) -> Void
    
    enum PINMode {
        case setup
        case verify
        case change
    }
    
    @State private var enteredPIN: String = ""
    @State private var confirmPIN: String = ""
    @State private var isConfirming: Bool = false
    @State private var currentPIN: String = ""
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    
    // Haptic feedback
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let notificationFeedback = UINotificationFeedbackGenerator()
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            headerView
            
            // PIN dots
            pinDotsView
            
            // Error message
            if showError {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .transition(.opacity)
            }
            
            // Lockout message
            if pinManager.isLockedOut {
                lockoutView
            }
            
            Spacer()
            
            // Keypad
            if !pinManager.isLockedOut {
                keypadView
            }
        }
        .padding()
        .animation(.easeInOut(duration: 0.2), value: showError)
        .animation(.easeInOut(duration: 0.2), value: enteredPIN)
    }
    
    // MARK: - Subviews
    
    private var headerView: some View {
        VStack(spacing: 8) {
            Image(systemName: mode == .verify ? "lock.fill" : "lock.badge.plus.fill")
                .font(.system(size: 40))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color(red: 212/255, green: 175/255, blue: 55/255),
                                 Color(red: 170/255, green: 140/255, blue: 44/255)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            
            Text(headerTitle)
                .font(.title2.weight(.semibold))
            
            Text(headerSubtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    private var headerTitle: String {
        switch mode {
        case .setup:
            return isConfirming ? "Confirm PIN" : "Create PIN"
        case .verify:
            return "Enter PIN"
        case .change:
            if currentPIN.isEmpty {
                return "Current PIN"
            } else if !isConfirming {
                return "New PIN"
            } else {
                return "Confirm New PIN"
            }
        }
    }
    
    private var headerSubtitle: String {
        switch mode {
        case .setup:
            return isConfirming ? "Re-enter your 6-digit PIN" : "Create a 6-digit PIN"
        case .verify:
            return "Enter your 6-digit PIN to unlock"
        case .change:
            if currentPIN.isEmpty {
                return "Enter your current PIN"
            } else {
                return isConfirming ? "Re-enter your new PIN" : "Enter a new 6-digit PIN"
            }
        }
    }
    
    private var pinDotsView: some View {
        HStack(spacing: 16) {
            ForEach(0..<6, id: \.self) { index in
                Circle()
                    .fill(index < enteredPIN.count ? Color.primary : Color.gray.opacity(0.3))
                    .frame(width: 16, height: 16)
                    .animation(.easeInOut(duration: 0.1), value: enteredPIN.count)
            }
        }
    }
    
    private var lockoutView: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.slash.fill")
                .font(.system(size: 30))
                .foregroundColor(.red)
            
            Text("Too many failed attempts")
                .font(.headline)
                .foregroundColor(.red)
            
            Text("Try again in \(pinManager.formattedLockoutTime)")
                .font(.title2.monospacedDigit())
                .foregroundColor(.secondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.1))
        )
    }
    
    private var keypadView: some View {
        VStack(spacing: 16) {
            ForEach(0..<3) { row in
                HStack(spacing: 24) {
                    ForEach(1...3, id: \.self) { col in
                        let number = row * 3 + col
                        keypadButton(String(number))
                    }
                }
            }
            
            // Bottom row: empty, 0, delete
            HStack(spacing: 24) {
                // Cancel or empty
                Button(action: { onComplete(false) }) {
                    Text("Cancel")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .frame(width: 80, height: 80)
                }
                
                keypadButton("0")
                
                // Delete
                Button(action: deleteDigit) {
                    Image(systemName: "delete.left")
                        .font(.title2)
                        .foregroundColor(.primary)
                        .frame(width: 80, height: 80)
                }
            }
        }
    }
    
    private func keypadButton(_ digit: String) -> some View {
        Button(action: { enterDigit(digit) }) {
            Text(digit)
                .font(.title.weight(.medium))
                .foregroundColor(.primary)
                .frame(width: 80, height: 80)
                .background(
                    Circle()
                        .fill(Color.gray.opacity(0.15))
                )
        }
    }
    
    // MARK: - Actions
    
    private func enterDigit(_ digit: String) {
        guard enteredPIN.count < 6 else { return }
        
        impactLight.impactOccurred()
        enteredPIN += digit
        showError = false
        
        // Check if complete
        if enteredPIN.count == 6 {
            handlePINComplete()
        }
    }
    
    private func deleteDigit() {
        guard !enteredPIN.isEmpty else { return }
        impactLight.impactOccurred()
        enteredPIN.removeLast()
    }
    
    private func handlePINComplete() {
        switch mode {
        case .setup:
            if !isConfirming {
                confirmPIN = enteredPIN
                enteredPIN = ""
                isConfirming = true
            } else {
                if enteredPIN == confirmPIN {
                    if pinManager.setPIN(enteredPIN) {
                        notificationFeedback.notificationOccurred(.success)
                        onComplete(true)
                    } else {
                        showErrorMessage("Failed to save PIN")
                    }
                } else {
                    showErrorMessage("PINs don't match")
                    enteredPIN = ""
                    confirmPIN = ""
                    isConfirming = false
                }
            }
            
        case .verify:
            if pinManager.verifyPIN(enteredPIN) {
                notificationFeedback.notificationOccurred(.success)
                onComplete(true)
            } else {
                showErrorMessage("Incorrect PIN")
                enteredPIN = ""
            }
            
        case .change:
            if currentPIN.isEmpty {
                if pinManager.verifyPIN(enteredPIN) {
                    currentPIN = enteredPIN
                    enteredPIN = ""
                } else {
                    showErrorMessage("Incorrect current PIN")
                    enteredPIN = ""
                }
            } else if !isConfirming {
                confirmPIN = enteredPIN
                enteredPIN = ""
                isConfirming = true
            } else {
                if enteredPIN == confirmPIN {
                    if pinManager.changePIN(currentPIN: currentPIN, newPIN: enteredPIN) {
                        notificationFeedback.notificationOccurred(.success)
                        onComplete(true)
                    } else {
                        showErrorMessage("Failed to change PIN")
                    }
                } else {
                    showErrorMessage("PINs don't match")
                    enteredPIN = ""
                    confirmPIN = ""
                    isConfirming = false
                }
            }
        }
    }
    
    private func showErrorMessage(_ message: String) {
        notificationFeedback.notificationOccurred(.error)
        errorMessage = message
        showError = true
    }
}

// MARK: - Preview

#Preview {
    PINEntryView(mode: .setup) { success in
        print("PIN setup: \(success)")
    }
}
