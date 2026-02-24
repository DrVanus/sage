//
//  AppCheckManager.swift
//  CryptoSage
//
//  Firebase App Check integration for secure Cloud Functions access
//  Prevents unauthorized API access from non-app clients
//

import Foundation
import FirebaseCore
import FirebaseAppCheck

/// Manages Firebase App Check configuration for secure Cloud Functions access
///
/// App Check helps protect your Cloud Functions from abuse by ensuring requests
/// come from your authentic app and not from unauthorized clients.
///
/// For production: Register your app with Apple's Device Check/App Attest
/// For development: Uses Debug provider (requires manual token registration)
final class AppCheckManager {

    static let shared = AppCheckManager()

    private init() {}

    /// Configure Firebase App Check
    /// Must be called BEFORE FirebaseApp.configure()
    func configure() {
        #if DEBUG
        // ═══════════════════════════════════════════════════════════════
        // DEBUG MODE: App Check Debug Provider
        // ═══════════════════════════════════════════════════════════════
        // For development and testing, we use the Debug provider.
        //
        // SETUP REQUIRED:
        // 1. Run the app once - it will log a debug token to the console
        // 2. Copy the debug token from the console (look for "App Check debug token:")
        // 3. Add it to Firebase Console:
        //    - Go to: Project Settings > App Check
        //    - Click "Manage debug tokens"
        //    - Add the token from the console
        // 4. The token is valid for 7 days
        //
        // The debug token will be printed to console on first launch.
        // ═══════════════════════════════════════════════════════════════

        let providerFactory = AppCheckDebugProviderFactory()
        AppCheck.setAppCheckProviderFactory(providerFactory)

        print("🔐 [App Check] Configured with DEBUG provider")
        print("🔐 [App Check] Look for debug token in console and register it in Firebase Console")

        #else
        // ═══════════════════════════════════════════════════════════════
        // PRODUCTION MODE: Device Check / App Attest Provider
        // ═══════════════════════════════════════════════════════════════
        // For production, we use Apple's Device Check (iOS 11+) or
        // App Attest (iOS 14+) for secure attestation.
        //
        // SETUP REQUIRED:
        // 1. Enable App Attest in Xcode:
        //    - Target > Signing & Capabilities > + Capability
        //    - Add "App Attest"
        //
        // 2. Register your app in Firebase Console:
        //    - Go to: Project Settings > App Check
        //    - Select your iOS app
        //    - Click "Register" under App Attest
        //    - Your app's bundle ID: com.dee.CryptoSage
        //
        // App Attest is automatically used on iOS 14+ devices.
        // Device Check is used as fallback on iOS 11-13.
        // ═══════════════════════════════════════════════════════════════

        let providerFactory = AppAttestProviderFactory()
        AppCheck.setAppCheckProviderFactory(providerFactory)

        print("🔐 [App Check] Configured with App Attest/Device Check provider")

        #endif
    }

    /// Get the current App Check token (for debugging)
    /// This is useful for verifying that App Check is working correctly
    func getToken(completion: @escaping (String?, Error?) -> Void) {
        AppCheck.appCheck().token(forcingRefresh: false) { token, error in
            if let error = error {
                print("❌ [App Check] Failed to get token: \(error.localizedDescription)")
                completion(nil, error)
                return
            }

            if let token = token?.token {
                print("✅ [App Check] Token retrieved successfully")
                print("   Token (first 20 chars): \(String(token.prefix(20)))...")
                completion(token, nil)
            } else {
                print("⚠️ [App Check] Token was nil")
                completion(nil, NSError(domain: "AppCheck", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Token was nil"
                ]))
            }
        }
    }

    /// Force refresh the App Check token (for testing)
    func refreshToken(completion: @escaping (Bool, Error?) -> Void) {
        AppCheck.appCheck().token(forcingRefresh: true) { token, error in
            if let error = error {
                print("❌ [App Check] Failed to refresh token: \(error.localizedDescription)")
                completion(false, error)
                return
            }

            if token != nil {
                print("✅ [App Check] Token refreshed successfully")
                completion(true, nil)
            } else {
                print("⚠️ [App Check] Refreshed token was nil")
                completion(false, NSError(domain: "AppCheck", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Refreshed token was nil"
                ]))
            }
        }
    }

    /// Verify that App Check is working (for debugging)
    /// Call this after app launch to ensure everything is configured correctly
    func verifySetup(completion: @escaping (Bool) -> Void) {
        getToken { token, error in
            if let error = error {
                print("❌ [App Check] Setup verification FAILED: \(error.localizedDescription)")
                completion(false)
                return
            }

            if token != nil {
                print("✅ [App Check] Setup verification PASSED")
                completion(true)
            } else {
                print("⚠️ [App Check] Setup verification FAILED: No token")
                completion(false)
            }
        }
    }
}
