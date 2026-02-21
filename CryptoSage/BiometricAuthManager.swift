//
//  BiometricAuthManager.swift
//  CryptoSage
//
//  Manages biometric (Face ID / Touch ID) authentication for app security.
//  Created for user data protection.
//

import Foundation
import LocalAuthentication
import SwiftUI

/// Singleton manager for biometric authentication with PIN fallback
final class BiometricAuthManager: ObservableObject {
    static let shared = BiometricAuthManager()
    
    /// Whether the user has enabled biometric lock in settings
    @AppStorage("enableBiometric") private(set) var isBiometricEnabled: Bool = false
    
    /// Whether the user has enabled PIN as a fallback
    @AppStorage("enablePINFallback") private(set) var isPINFallbackEnabled: Bool = false
    
    /// Whether the app is currently locked (needs authentication)
    @Published var isLocked: Bool = true
    
    /// Error message to display if authentication fails
    @Published var authError: String?
    
    /// The type of biometric available on this device
    @Published private(set) var biometricType: BiometricType = .none
    
    /// Reference to PIN manager for fallback authentication
    let pinManager = PINAuthManager.shared
    
    private let isSimulatorRuntime: Bool = {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }()
    
    enum BiometricType {
        case none
        case touchID
        case faceID
        
        var displayName: String {
            switch self {
            case .none: return "Passcode"
            case .touchID: return "Touch ID"
            case .faceID: return "Face ID"
            }
        }
        
        var iconName: String {
            switch self {
            case .none: return "lock.fill"
            case .touchID: return "touchid"
            case .faceID: return "faceid"
            }
        }
    }
    
    private init() {
        if isSimulatorRuntime {
            // Simulator stability: never allow auth lock to block startup.
            // Face ID/Touch ID/passcode flows are unreliable in sim and can
            // leave the lock overlay permanently visible over Home.
            isBiometricEnabled = false
            isPINFallbackEnabled = false
            isLocked = false
            biometricType = .none
            authError = nil
            return
        }
        detectBiometricType()
        // If biometric is not enabled, don't lock the app
        if !isBiometricEnabled {
            isLocked = false
        }
    }
    
    /// Detect what biometric authentication is available on this device
    func detectBiometricType() {
        let context = LAContext()
        var error: NSError?
        
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            biometricType = .none
            return
        }
        
        switch context.biometryType {
        case .touchID:
            biometricType = .touchID
        case .faceID:
            biometricType = .faceID
        case .opticID:
            biometricType = .faceID // Treat Optic ID like Face ID for UI purposes
        case .none:
            biometricType = .none
        @unknown default:
            biometricType = .none
        }
    }
    
    /// Check if biometric authentication is available on this device
    var canUseBiometric: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }
    
    /// Check if device has any authentication method (biometric or passcode)
    var canUseDeviceAuth: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }
    
    /// Authenticate the user using biometrics or device passcode
    /// - Parameter reason: The reason string shown to the user
    /// - Returns: True if authentication succeeded
    @MainActor
    func authenticate(reason: String = "Unlock CryptoSage to access your portfolio") async -> Bool {
        if isSimulatorRuntime {
            isLocked = false
            authError = nil
            return true
        }
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"
        context.localizedFallbackTitle = "Use Passcode"
        
        var error: NSError?
        
        // Use deviceOwnerAuthentication to allow passcode fallback
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            authError = error?.localizedDescription ?? "Authentication not available"
            return false
        }
        
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )
            
            if success {
                isLocked = false
                authError = nil
                return true
            } else {
                authError = "Authentication failed"
                return false
            }
        } catch let authError as LAError {
            switch authError.code {
            case .userCancel:
                self.authError = nil // User cancelled, no error message needed
            case .userFallback:
                self.authError = nil // User chose passcode, handled by system
            case .biometryNotAvailable:
                self.authError = "Biometric authentication not available"
            case .biometryNotEnrolled:
                self.authError = "No biometrics enrolled. Please set up Face ID or Touch ID in Settings."
            case .biometryLockout:
                self.authError = "Too many failed attempts. Please use your device passcode."
            case .authenticationFailed:
                self.authError = "Authentication failed. Please try again."
            default:
                self.authError = authError.localizedDescription
            }
            return false
        } catch {
            self.authError = error.localizedDescription
            return false
        }
    }
    
    /// Lock the app (call when app goes to background if biometric is enabled)
    func lockApp() {
        if isSimulatorRuntime { return }
        if isBiometricEnabled {
            isLocked = true
            authError = nil
        }
    }
    
    /// Enable biometric lock
    func enableBiometric() {
        isBiometricEnabled = true
        isLocked = false // Don't lock immediately after enabling
    }
    
    /// Disable biometric lock
    func disableBiometric() {
        isBiometricEnabled = false
        isLocked = false
    }
    
    /// Toggle biometric setting with authentication check
    @MainActor
    func toggleBiometric() async -> Bool {
        if isBiometricEnabled {
            // Disabling - require authentication first
            let authenticated = await authenticate(reason: "Authenticate to disable \(biometricType.displayName)")
            if authenticated {
                disableBiometric()
                return true
            }
            return false
        } else {
            // Enabling - verify it works first
            let authenticated = await authenticate(reason: "Authenticate to enable \(biometricType.displayName)")
            if authenticated {
                enableBiometric()
                return true
            }
            return false
        }
    }
    
    // MARK: - PIN Fallback Support
    
    /// Whether PIN can be used as fallback (PIN is set up)
    var canUsePINFallback: Bool {
        pinManager.isPINSet
    }
    
    /// Whether any lock method is enabled (biometric or PIN)
    var isAnyLockEnabled: Bool {
        isBiometricEnabled || (isPINFallbackEnabled && canUsePINFallback)
    }
    
    /// Enable PIN fallback
    func enablePINFallback() {
        isPINFallbackEnabled = true
    }
    
    /// Disable PIN fallback
    func disablePINFallback() {
        isPINFallbackEnabled = false
    }
    
    /// Unlock with PIN
    /// - Parameter pin: The PIN to verify
    /// - Returns: True if PIN is correct and app is unlocked
    func unlockWithPIN(_ pin: String) -> Bool {
        if pinManager.verifyPIN(pin) {
            isLocked = false
            authError = nil
            return true
        }
        authError = "Incorrect PIN"
        return false
    }
    
    /// Lock the app considering both biometric and PIN settings
    func lockAppIfNeeded() {
        if isSimulatorRuntime { return }
        if isBiometricEnabled || (isPINFallbackEnabled && canUsePINFallback) {
            isLocked = true
            authError = nil
        }
    }
}

// MARK: - Info.plist Requirement
/*
 IMPORTANT: For Face ID, you must add the following to your Info.plist:
 
 <key>NSFaceIDUsageDescription</key>
 <string>CryptoSage uses Face ID to protect your portfolio and trading data.</string>
 
 This is already handled in the app, but if you see Face ID not working,
 verify this key exists in your Info.plist.
*/
