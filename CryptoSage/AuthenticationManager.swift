//
//  AuthenticationManager.swift
//  CryptoSage
//
//  Created for CryptoSage AI backend integration.
//
//  Manages Apple Sign-In authentication with Firebase Auth.
//  Provides a seamless sign-in experience with cross-device sync.
//

import Foundation
import AuthenticationServices
import CryptoKit
import Combine
import FirebaseAuth

// SECURITY: Debug-only logging to prevent PII (user IDs, emails, names) from
// appearing in production device logs. In release builds this compiles to nothing.
@inline(__always)
private func authLog(_ message: @autoclosure () -> String) {
    #if DEBUG
    print(message())
    #endif
}

// MARK: - Authentication State

enum AuthenticationState {
    case unknown
    case signedOut
    case signingIn
    case signedIn(User)
    case error(String)
}

// MARK: - User Model

struct User: Codable, Identifiable {
    let id: String // Firebase UID
    let email: String?
    let displayName: String?
    let photoURL: String?
    var subscriptionTier: String
    let createdAt: Date
    var lastSignIn: Date
    
    init(id: String, email: String?, displayName: String?, subscriptionTier: String = "free") {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.photoURL = nil
        self.subscriptionTier = subscriptionTier
        self.createdAt = Date()
        self.lastSignIn = Date()
    }
}

// MARK: - Authentication Manager

/// Manages user authentication with Apple Sign-In and Firebase
@MainActor
final class AuthenticationManager: NSObject, ObservableObject {
    static let shared = AuthenticationManager()
    
    // MARK: - Published State
    
    @Published private(set) var state: AuthenticationState = .unknown
    @Published private(set) var currentUser: User? = nil
    @Published private(set) var isAuthenticated: Bool = false
    
    // MARK: - Private Properties
    
    private var currentNonce: String? = nil
    private let userDefaultsKey = "AuthenticatedUser"
    private let keychainService = "AuthenticatedUser"
    private let keychainAccount = "session"
    private var hasScheduledDeferredFirestoreSync = false
    private var tokenRefreshTask: Task<Void, Never>?

    // MARK: - Initialization

    private override init() {
        super.init()
        migrateSessionFromUserDefaultsToKeychain()
        restoreUserSession()
    }

    // MARK: - Migration (UserDefaults → Keychain)

    /// One-time migration: move User session data from UserDefaults to Keychain.
    /// After migration the UserDefaults entry is removed so it only runs once.
    private func migrateSessionFromUserDefaultsToKeychain() {
        // Only migrate if data exists in UserDefaults but NOT in Keychain
        guard let legacyData = UserDefaults.standard.data(forKey: userDefaultsKey),
              KeychainHelper.shared.readData(service: keychainService, account: keychainAccount) == nil else {
            return
        }

        do {
            try KeychainHelper.shared.saveData(legacyData, service: keychainService, account: keychainAccount)
            UserDefaults.standard.removeObject(forKey: userDefaultsKey)
            authLog("[AuthenticationManager] Migrated session data from UserDefaults to Keychain")
        } catch {
            // Migration failed — leave UserDefaults intact so data is not lost.
            // The next launch will retry.
            authLog("[AuthenticationManager] Keychain migration failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Session Restoration
    
    /// Restore user session from saved credentials
    private func restoreUserSession() {
        // Check if Firebase Auth has a current user (persisted by the SDK)
        if let firebaseUser = Auth.auth().currentUser {
            // Firebase has a session — also verify Apple credential state
            if let userData = KeychainHelper.shared.readData(service: keychainService, account: keychainAccount),
               let user = try? JSONDecoder().decode(User.self, from: userData) {

                verifyAppleCredentialState(for: user) { [weak self] isValid in
                    guard let self = self else { return }
                    
                    Task { @MainActor in
                        if isValid {
                            self.currentUser = user
                            self.isAuthenticated = true
                            self.state = .signedIn(user)
                            
                            self.syncUserToProfile(user)
                            
                            // Get a fresh Firebase ID token for API calls
                            if let token = try? await firebaseUser.getIDToken() {
                                FirebaseService.shared.setAuthToken(token, userId: user.id)
                                self.startTokenRefreshLoop()
                            } else {
                                FirebaseService.shared.setAuthToken(nil, userId: user.id)
                            }

                            self.scheduleDeferredFirestoreSyncBatches(reason: "restore-session")
                            
                            authLog("[AuthenticationManager] Restored Firebase session for user: \(user.id)")
                        } else {
                            authLog("[AuthenticationManager] Apple credential revoked, signing out")
                            self.signOut()
                        }
                    }
                }
            } else {
                // Firebase user exists but no local User data — rebuild from Firebase
                let user = User(
                    id: firebaseUser.uid,
                    email: firebaseUser.email,
                    displayName: firebaseUser.displayName,
                    subscriptionTier: "free"
                )
                self.currentUser = user
                self.isAuthenticated = true
                self.state = .signedIn(user)
                self.syncUserToProfile(user)
                
                if let userData = try? JSONEncoder().encode(user) {
                    try? KeychainHelper.shared.saveData(userData, service: keychainService, account: keychainAccount)
                }

                Task { @MainActor in
                    if let token = try? await firebaseUser.getIDToken() {
                        FirebaseService.shared.setAuthToken(token, userId: user.id)
                        self.startTokenRefreshLoop()
                    }
                }

                // Defer Firestore sync startup via centralized scheduler.
                scheduleDeferredFirestoreSyncBatches(reason: "restore-firebase-only")
                
                authLog("[AuthenticationManager] Rebuilt session from Firebase Auth: \(user.id)")
            }
        } else if let userData = KeychainHelper.shared.readData(service: keychainService, account: keychainAccount),
                  let user = try? JSONDecoder().decode(User.self, from: userData) {
            // Legacy: Local session exists but no Firebase Auth session
            // Verify Apple credential state and restore if valid
            verifyAppleCredentialState(for: user) { [weak self] isValid in
                guard let self = self else { return }
                
                Task { @MainActor in
                    if isValid {
                        self.currentUser = user
                        self.isAuthenticated = true
                        self.state = .signedIn(user)
                        self.syncUserToProfile(user)
                        FirebaseService.shared.setAuthToken(nil, userId: user.id)
                        
                        self.scheduleDeferredFirestoreSyncBatches(reason: "restore-legacy-session")
                        
                        authLog("[AuthenticationManager] Restored legacy session for user: \(user.id)")
                    } else {
                        authLog("[AuthenticationManager] Apple credential revoked, signing out")
                        self.signOut()
                    }
                }
            }
        } else {
            self.state = .signedOut
        }
    }
    
    /// Verify Apple credential state (required by Apple for Sign in with Apple)
    /// Users can revoke app access from Settings > Apple ID > Password & Security > Apps Using Apple ID
    private func verifyAppleCredentialState(for user: User, completion: @escaping (Bool) -> Void) {
        // Extract the Apple user identifier from our stored user ID
        // Our format is "apple_{hash}" - we need the original Apple user ID
        // If we don't have it stored, we can't verify (treat as valid for backward compat)
        guard let appleUserID = UserDefaults.standard.string(forKey: "AppleUserID_\(user.id)") else {
            // No Apple user ID stored - likely a migration case, treat as valid
            authLog("[AuthenticationManager] No Apple user ID stored, skipping verification")
            completion(true)
            return
        }
        
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        appleIDProvider.getCredentialState(forUserID: appleUserID) { credentialState, error in
            if let error = error {
                authLog("[AuthenticationManager] Credential state check failed: \(error.localizedDescription)")
                // On error, be permissive and allow access (network issues shouldn't lock users out)
                completion(true)
                return
            }
            
            switch credentialState {
            case .authorized:
                // User is still authorized
                completion(true)
            case .revoked:
                // User has revoked access - must sign out
                authLog("[AuthenticationManager] Apple credential revoked by user")
                completion(false)
            case .notFound:
                // User ID not found - credential is invalid
                authLog("[AuthenticationManager] Apple credential not found")
                completion(false)
            case .transferred:
                // Account was transferred to a different team (rare)
                authLog("[AuthenticationManager] Apple credential transferred")
                completion(false)
            @unknown default:
                // Unknown state - be permissive
                completion(true)
            }
        }
    }
    
    // MARK: - Apple Sign-In
    
    /// Prepare the Apple Sign-In request with a nonce for Firebase Auth verification.
    /// Call this from `SignInWithAppleButton(onRequest:)` to set the nonce on the request.
    func prepareAppleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        do {
            let nonce = try randomNonceString()
            currentNonce = nonce
            request.requestedScopes = [.fullName, .email]
            request.nonce = sha256(nonce)
        } catch {
            authLog("[AuthenticationManager] Failed to generate nonce: \(error)")
        }
    }
    
    /// Start the Apple Sign-In flow (for programmatic use)
    func signInWithApple() {
        do {
            let nonce = try randomNonceString()
            currentNonce = nonce
            
            let request = ASAuthorizationAppleIDProvider().createRequest()
            request.requestedScopes = [.fullName, .email]
            request.nonce = sha256(nonce)
            
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
            
            state = .signingIn
        } catch {
            // Handle nonce generation failure gracefully
            state = .error("Unable to start sign-in: \(error.localizedDescription)")
        }
    }
    
    /// Handle the result from SignInWithAppleButton (SwiftUI)
    /// Use this when using SwiftUI's native SignInWithAppleButton.
    /// IMPORTANT: `prepareAppleSignInRequest(_:)` must be called in the `onRequest` callback
    /// to set the nonce that Firebase Auth requires for verification.
    func handleAppleSignIn(result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                state = .error("Invalid credential type")
                return
            }
            
            guard let appleIDToken = appleIDCredential.identityToken,
                  let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                state = .error("Unable to fetch identity token")
                return
            }
            
            let fullName = appleIDCredential.fullName
            let email = appleIDCredential.email
            let appleUserID = appleIDCredential.user
            
            // Use the nonce that was set in prepareAppleSignInRequest(_:)
            guard let nonce = currentNonce else {
                // Fallback: generate a new nonce if prepareAppleSignInRequest wasn't called
                // (won't match what Apple signed, so Firebase will reject — log a warning)
                authLog("[AuthenticationManager] WARNING: No nonce found. Did you call prepareAppleSignInRequest in onRequest?")
                state = .error("Authentication configuration error. Please try again.")
                return
            }
            
            Task { @MainActor in
                do {
                    try await self.exchangeAppleCredentialForFirebase(
                        idToken: idTokenString,
                        nonce: nonce,
                        fullName: fullName,
                        email: email,
                        appleUserID: appleUserID
                    )
                } catch {
                    self.state = .error(error.localizedDescription)
                }
            }
            
        case .failure(let error):
            let authError = error as? ASAuthorizationError
            switch authError?.code {
            case .canceled:
                state = .signedOut
            default:
                state = .error(error.localizedDescription)
            }
        }
    }
    
    // MARK: - Email/Password Authentication
    
    /// Sign up a new user with email and password
    func signUpWithEmail(email: String, password: String, displayName: String?) async throws {
        state = .signingIn
        
        do {
            let authResult = try await Auth.auth().createUser(withEmail: email, password: password)
            let firebaseUser = authResult.user
            
            // Set display name if provided
            if let displayName = displayName, !displayName.isEmpty {
                let changeRequest = firebaseUser.createProfileChangeRequest()
                changeRequest.displayName = displayName
                try? await changeRequest.commitChanges()
            }
            
            // Send email verification
            try? await firebaseUser.sendEmailVerification()
            
            try await completeFirebaseSignIn(
                firebaseUser: firebaseUser,
                displayName: displayName ?? firebaseUser.displayName,
                email: email
            )
            
            authLog("[AuthenticationManager] User signed up with email: \(firebaseUser.uid)")
        } catch {
            state = .error(error.localizedDescription)
            throw error
        }
    }
    
    /// Sign in an existing user with email and password
    func signInWithEmail(email: String, password: String) async throws {
        state = .signingIn
        
        do {
            let authResult = try await Auth.auth().signIn(withEmail: email, password: password)
            let firebaseUser = authResult.user
            
            try await completeFirebaseSignIn(
                firebaseUser: firebaseUser,
                displayName: firebaseUser.displayName,
                email: firebaseUser.email ?? email
            )
            
            authLog("[AuthenticationManager] User signed in with email: \(firebaseUser.uid)")
        } catch {
            state = .error(error.localizedDescription)
            throw error
        }
    }
    
    /// Send a password reset email
    func resetPassword(email: String) async throws {
        try await Auth.auth().sendPasswordReset(withEmail: email)
        authLog("[AuthenticationManager] Password reset email sent to: \(email)")
    }
    
    /// Send email verification to the current user
    func sendEmailVerification() async throws {
        guard let user = Auth.auth().currentUser else { return }
        try await user.sendEmailVerification()
    }
    
    // MARK: - Google Sign-In
    
    /// Sign in with Google credential (called after GoogleSignIn SDK flow)
    func signInWithGoogleCredential(idToken: String, accessToken: String) async throws {
        state = .signingIn
        
        do {
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: accessToken
            )
            
            let authResult = try await Auth.auth().signIn(with: credential)
            let firebaseUser = authResult.user
            
            try await completeFirebaseSignIn(
                firebaseUser: firebaseUser,
                displayName: firebaseUser.displayName,
                email: firebaseUser.email
            )
            
            authLog("[AuthenticationManager] User signed in with Google: \(firebaseUser.uid)")
        } catch {
            state = .error(error.localizedDescription)
            throw error
        }
    }
    
    // MARK: - Shared Post-Auth Flow
    
    /// Complete sign-in after Firebase Auth succeeds (shared by Apple, Email, Google)
    private func completeFirebaseSignIn(
        firebaseUser: FirebaseAuth.User,
        displayName: String?,
        email: String?
    ) async throws {
        let firebaseIDToken = try await firebaseUser.getIDToken()
        let userId = firebaseUser.uid
        
        let user = User(
            id: userId,
            email: email ?? firebaseUser.email,
            displayName: displayName ?? firebaseUser.displayName,
            subscriptionTier: "free"
        )
        
        self.currentUser = user
        self.isAuthenticated = true
        self.state = .signedIn(user)
        
        // Persist session to Keychain
        if let userData = try? JSONEncoder().encode(user) {
            try? KeychainHelper.shared.saveData(userData, service: keychainService, account: keychainAccount)
        }

        // Sync profile data
        syncUserToProfile(user)
        
        // Update FirebaseService
        FirebaseService.shared.setAuthToken(firebaseIDToken, userId: userId)
        startTokenRefreshLoop()

        // Start Firestore sync in deferred batches (same as restored sessions)
        scheduleDeferredFirestoreSyncBatches(reason: "post-sign-in")
    }
    
    // MARK: - Sign Out
    
    /// Sign out the current user
    func signOut() {
        tokenRefreshTask?.cancel()
        tokenRefreshTask = nil
        hasScheduledDeferredFirestoreSync = false
        
        // Stop Firestore sync before clearing auth
        FavoritesManager.shared.stopFirestoreSync()
        NotificationsManager.shared.stopFirestoreSync()
        ConversationSyncService.shared.stopFirestoreSync()
        PredictionAccuracyService.shared.stopFirestoreSync()
        ProfileSyncService.shared.stopFirestoreSync()
        PaperTradingManager.shared.stopFirestoreSync()
        AIPortfolioMonitor.shared.stopMonitoring()

        // Clean up Apple user ID key before clearing user
        if let userId = currentUser?.id {
            UserDefaults.standard.removeObject(forKey: "AppleUserID_\(userId)")
        }

        // Deactivate FCM token so push notifications stop for this user
        if let fcmToken = PushNotificationManager.shared.fcmToken {
            PushNotificationManager.shared.removeFCMTokenFromFirestore(fcmToken)
        }
        
        currentUser = nil
        isAuthenticated = false
        state = .signedOut
        
        // Clear saved session from Keychain
        try? KeychainHelper.shared.delete(service: keychainService, account: keychainAccount)
        
        // Reset profile to defaults (user can still use app without account)
        clearProfileData()
        
        // Sign out from Firebase Auth
        try? Auth.auth().signOut()
        
        // Clear Firebase service auth state
        FirebaseService.shared.clearAuth()
        
        authLog("[AuthenticationManager] User signed out")
    }
    
    // MARK: - Profile Update
    
    /// Update the user's display name on Firebase Auth so it persists across reinstalls.
    /// Call this whenever the user edits their display name in the profile view.
    func updateDisplayName(_ newName: String) {
        guard !newName.isEmpty else { return }

        Task { @MainActor in
            do {
                let changeRequest = Auth.auth().currentUser?.createProfileChangeRequest()
                changeRequest?.displayName = newName
                try await changeRequest?.commitChanges()
                
                // Update local User model
                if var user = currentUser {
                    user = User(
                        id: user.id,
                        email: user.email,
                        displayName: newName,
                        subscriptionTier: user.subscriptionTier
                    )
                    currentUser = user
                    state = .signedIn(user)
                    
                    // Persist updated session to Keychain
                    if let userData = try? JSONEncoder().encode(user) {
                        try? KeychainHelper.shared.saveData(userData, service: keychainService, account: keychainAccount)
                    }
                }
                
                authLog("[AuthenticationManager] Display name updated to: \(newName)")
            } catch {
                authLog("[AuthenticationManager] Failed to update display name: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Profile Sync
    
    /// Sync authenticated user data to profile AppStorage keys
    /// This bridges AuthenticationManager → Profile views
    /// Only sets defaults when local storage is empty (avoids overwriting
    /// cloud-restored values like a custom display name with the auth provider name).
    private func syncUserToProfile(_ user: User) {
        let defaults = UserDefaults.standard
        
        // Only set display name from auth provider if no local name exists yet.
        // ProfileSyncService will restore the user's preferred name from Firestore.
        let existingName = defaults.string(forKey: "profile.displayName") ?? ""
        if existingName.isEmpty, let displayName = user.displayName, !displayName.isEmpty {
            defaults.set(displayName, forKey: "profile.displayName")
        }
        
        // Email — always update from auth provider (authoritative source)
        if let email = user.email, !email.isEmpty {
            defaults.set(email, forKey: "profile.email")
        }
        
        authLog("[AuthenticationManager] Synced user profile: \(user.displayName ?? "no name"), \(user.email ?? "no email")")
    }
    
    /// Clear profile data on sign out (reset to defaults)
    private func clearProfileData() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "profile.displayName")
        defaults.removeObject(forKey: "profile.email")
        defaults.removeObject(forKey: "profile.phone")
        defaults.removeObject(forKey: "profile.bio")
        defaults.removeObject(forKey: "profile.avatarPresetId")
        defaults.removeObject(forKey: "profile.imagePath")
        defaults.removeObject(forKey: "profile.cloudImageURL")
        
        authLog("[AuthenticationManager] Cleared profile data")
    }
    
    // MARK: - Token Exchange
    
    /// Exchange Apple credential for Firebase Auth token
    /// Uses Firebase Auth SDK to create/sign-in user with OAuthProvider credential
    private func exchangeAppleCredentialForFirebase(
        idToken: String,
        nonce: String,
        fullName: PersonNameComponents?,
        email: String?,
        appleUserID: String? = nil
    ) async throws {
        // Build display name from Apple-provided name components
        let displayName: String?
        if let fullName = fullName {
            displayName = [fullName.givenName, fullName.familyName]
                .compactMap { $0 }
                .joined(separator: " ")
                .nilIfEmpty
        } else {
            displayName = nil
        }
        
        // Create Firebase OAuthProvider credential from Apple's ID token + nonce
        let credential = OAuthProvider.credential(
            providerID: AuthProviderID.apple,
            idToken: idToken,
            rawNonce: nonce
        )
        
        // Sign in to Firebase with the Apple credential
        let authResult = try await Auth.auth().signIn(with: credential)
        let firebaseUser = authResult.user
        
        // Update display name on Firebase if Apple provided one (only on first sign-in)
        if let displayName = displayName, firebaseUser.displayName == nil || firebaseUser.displayName?.isEmpty == true {
            let changeRequest = firebaseUser.createProfileChangeRequest()
            changeRequest.displayName = displayName
            try? await changeRequest.commitChanges()
        }
        
        // Get the Firebase ID token for authenticated API calls
        let firebaseIDToken = try await firebaseUser.getIDToken()
        
        // Use Firebase UID as the canonical user identifier
        let userId = firebaseUser.uid
        
        // Resolve display name: Apple-provided > Firebase profile > nil
        let resolvedDisplayName = displayName ?? firebaseUser.displayName
        // Resolve email: Apple-provided > Firebase profile > nil
        let resolvedEmail = email ?? firebaseUser.email
        
        let user = User(
            id: userId,
            email: resolvedEmail,
            displayName: resolvedDisplayName,
            subscriptionTier: "free"
        )
        
        // Save user
        self.currentUser = user
        self.isAuthenticated = true
        self.state = .signedIn(user)
        
        // Persist session to Keychain
        if let userData = try? JSONEncoder().encode(user) {
            try? KeychainHelper.shared.saveData(userData, service: keychainService, account: keychainAccount)
        }

        // Store Apple user ID for credential state verification (required by Apple)
        if let appleUserID = appleUserID {
            UserDefaults.standard.set(appleUserID, forKey: "AppleUserID_\(userId)")
        }
        
        // Sync profile data to AppStorage keys used by ProfileView/ProfileHeaderView
        syncUserToProfile(user)
        
        // Update FirebaseService with the real Firebase ID token
        FirebaseService.shared.setAuthToken(firebaseIDToken, userId: userId)
        startTokenRefreshLoop()

        // Start Firestore sync in deferred batches (same as restored sessions)
        scheduleDeferredFirestoreSyncBatches(reason: "post-apple-exchange")
        
        authLog("[AuthenticationManager] User signed in via Firebase Auth: \(userId)")
    }
    
    // MARK: - Deferred Firestore Sync Orchestration
    
    /// Centralized startup orchestration for user-data Firestore listeners.
    /// Keeps listener startup single-owner and staggered to avoid memory spikes.
    private func scheduleDeferredFirestoreSyncBatches(reason: String) {
        guard !hasScheduledDeferredFirestoreSync else { return }
        hasScheduledDeferredFirestoreSync = true
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(nanoseconds: 15_000_000_000) // 15s
            guard self.isAuthenticated else { return }
            
            let availMB = Double(os_proc_available_memory()) / (1024 * 1024)
            if availMB > 0, availMB < 1200 {
                authLog("[AuthenticationManager] Skipping Firestore sync batch 1 (\(reason)) — only \(Int(availMB)) MB available")
                return
            }
            
            FavoritesManager.shared.startFirestoreSyncIfAuthenticated()
            NotificationsManager.shared.startFirestoreSyncIfAuthenticated()
        }
        
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(nanoseconds: 30_000_000_000) // 30s
            guard self.isAuthenticated else { return }
            
            let availMB = Double(os_proc_available_memory()) / (1024 * 1024)
            if availMB > 0, availMB < 1200 {
                authLog("[AuthenticationManager] Skipping Firestore sync batch 2 (\(reason)) — only \(Int(availMB)) MB available")
                return
            }
            
            ConversationSyncService.shared.startFirestoreSyncIfAuthenticated()
            PredictionAccuracyService.shared.startFirestoreSyncIfAuthenticated()
            ProfileSyncService.shared.startFirestoreSyncIfAuthenticated()
            PaperTradingManager.shared.startFirestoreSyncIfAuthenticated()
        }
    }
    
    // MARK: - Token Refresh

    /// Periodically refreshes the Firebase ID token before it expires (every 45 min).
    /// Firebase ID tokens expire after 60 minutes; refreshing at 45 min ensures
    /// authenticated Cloud Function calls never silently fail with 401.
    private func startTokenRefreshLoop() {
        tokenRefreshTask?.cancel()
        tokenRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                // Refresh every 45 minutes (tokens expire at 60 min)
                try? await Task.sleep(nanoseconds: 45 * 60 * 1_000_000_000)
                guard !Task.isCancelled else { break }
                guard let firebaseUser = Auth.auth().currentUser,
                      let self = self else { break }
                do {
                    let newToken = try await firebaseUser.getIDTokenResult(forcingRefresh: true).token
                    await MainActor.run {
                        FirebaseService.shared.setAuthToken(newToken, userId: firebaseUser.uid)
                    }
                    authLog("[AuthenticationManager] Firebase token refreshed")
                } catch {
                    authLog("[AuthenticationManager] Token refresh failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Helpers
    
    /// Error type for nonce generation failures
    enum NonceError: Error, LocalizedError {
        case secRandomFailed(OSStatus)
        
        var errorDescription: String? {
            switch self {
            case .secRandomFailed(let status):
                return "Security random generation failed (OSStatus: \(status))"
            }
        }
    }
    
    /// Generate a random nonce for Apple Sign-In
    /// - Throws: NonceError if SecRandomCopyBytes fails (extremely rare)
    private func randomNonceString(length: Int = 32) throws -> String {
        guard length > 0 else { throw NonceError.secRandomFailed(-1) }
        var randomBytes = [UInt8](repeating: 0, count: length)
        let errorCode = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        if errorCode != errSecSuccess {
            // Log the error instead of crashing
            authLog("[AuthenticationManager] SecRandomCopyBytes failed with OSStatus \(errorCode)")
            throw NonceError.secRandomFailed(errorCode)
        }
        
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        let nonce = randomBytes.map { byte in
            charset[Int(byte) % charset.count]
        }
        return String(nonce)
    }
    
    /// SHA256 hash the nonce
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AuthenticationManager: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            Task { @MainActor in
                self.state = .error("Invalid credential type")
            }
            return
        }
        
        guard let appleIDToken = appleIDCredential.identityToken,
              let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            Task { @MainActor in
                self.state = .error("Unable to fetch identity token")
            }
            return
        }
        
        let fullName = appleIDCredential.fullName
        let email = appleIDCredential.email
        let appleUserID = appleIDCredential.user  // Store for credential state verification
        
        Task { @MainActor in
            guard let nonce = self.currentNonce else {
                self.state = .error("Invalid state: A login callback was received, but no login request was sent.")
                return
            }
            
            do {
                try await self.exchangeAppleCredentialForFirebase(
                    idToken: idTokenString,
                    nonce: nonce,
                    fullName: fullName,
                    email: email,
                    appleUserID: appleUserID
                )
            } catch {
                self.state = .error(error.localizedDescription)
            }
        }
    }
    
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        // Handle error
        let authError = error as? ASAuthorizationError
        
        Task { @MainActor in
            switch authError?.code {
            case .canceled:
                self.state = .signedOut
            case .failed:
                self.state = .error("Sign in failed. Please try again.")
            case .invalidResponse:
                self.state = .error("Invalid response from Apple.")
            case .notHandled:
                self.state = .error("Sign in not handled.")
            case .unknown:
                self.state = .error("Unknown error occurred.")
            case .notInteractive:
                self.state = .error("Sign in requires interaction.")
            case .matchedExcludedCredential:
                self.state = .error("Credential was excluded.")
            default:
                self.state = .error(error.localizedDescription)
            }
        }
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AuthenticationManager: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = scene.windows.first else {
                return UIWindow()
            }
            return window
        }
    }
}

// MARK: - String Extension

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

