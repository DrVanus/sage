//
//  ProfileSyncService.swift
//  CryptoSage
//
//  Syncs user profile data (display name, bio, avatar, profile image) to
//  Firestore and Firebase Storage so it survives app reinstalls and works
//  across devices.
//
//  Firestore path:  users/{userId}/profile/data
//  Storage path:    profile_images/{userId}/profile.jpg
//

import Foundation
import FirebaseFirestore
import FirebaseStorage
import UIKit
import os

@MainActor
final class ProfileSyncService: ObservableObject {
    static let shared = ProfileSyncService()
    
    // MARK: - Published State
    
    /// Whether Firestore profile sync is currently active
    @Published private(set) var isFirestoreSyncActive: Bool = false
    
    // MARK: - Private Properties
    
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private var firestoreListener: ListenerRegistration?
    private var isApplyingFirestoreUpdate = false // Prevent sync loops
    private let logger = Logger(subsystem: "CryptoSage", category: "ProfileSyncService")
    
    /// Debounce timer for batching rapid profile changes
    private var syncDebounceTimer: Timer?
    private let syncDebounceInterval: TimeInterval = 1.0
    
    deinit {
        firestoreListener?.remove()
    }
    
    // MARK: - AppStorage Keys (must match ProfileView)
    
    private static let displayNameKey = "profile.displayName"
    private static let emailKey = "profile.email"
    private static let phoneKey = "profile.phone"
    private static let bioKey = "profile.bio"
    private static let imagePathKey = "profile.imagePath"
    private static let avatarPresetIdKey = "profile.avatarPresetId"
    private static let profileImageURLKey = "profile.cloudImageURL"
    
    private init() {}
    
    // MARK: - Public Sync API
    
    /// Start listening to Firestore for profile changes if user is authenticated.
    /// Called after sign-in completes.
    func startFirestoreSyncIfAuthenticated() {
        Task { @MainActor in
            guard AuthenticationManager.shared.isAuthenticated,
                  let userId = AuthenticationManager.shared.currentUser?.id else {
                logger.debug("🔥 [ProfileSync] Not authenticated, skipping Firestore sync")
                return
            }
            
            startFirestoreListener(userId: userId)
        }
    }
    
    /// Stop Firestore listener. Called on sign-out.
    func stopFirestoreSync() {
        firestoreListener?.remove()
        firestoreListener = nil
        isFirestoreSyncActive = false
        hasCompletedInitialFetch = false
        syncDebounceTimer?.invalidate()
        syncDebounceTimer = nil
        logger.info("🔥 [ProfileSync] Stopped Firestore sync")
    }
    
    /// Trigger a debounced sync of current profile data to Firestore.
    /// Call this whenever the user edits profile fields.
    func syncProfileToFirestore() {
        guard !isApplyingFirestoreUpdate else { return }
        
        syncDebounceTimer?.invalidate()
        syncDebounceTimer = Timer.scheduledTimer(withTimeInterval: syncDebounceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.uploadProfileToFirestore()
            }
        }
    }
    
    /// Upload a profile image to Firebase Storage and sync the URL to Firestore.
    func uploadProfileImage(_ image: UIImage) {
        Task { @MainActor in
            guard AuthenticationManager.shared.isAuthenticated,
                  let userId = AuthenticationManager.shared.currentUser?.id else {
                logger.debug("🔥 [ProfileSync] Not authenticated, skipping image upload")
                return
            }
            
            guard let imageData = image.jpegData(compressionQuality: 0.7) else {
                logger.error("🔥 [ProfileSync] Failed to convert image to JPEG data")
                return
            }
            
            let storageRef = storage.reference().child("profile_images/\(userId)/profile.jpg")
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            
            do {
                _ = try await storageRef.putDataAsync(imageData, metadata: metadata)
                let downloadURL = try await storageRef.downloadURL()
                
                // Save cloud URL locally
                UserDefaults.standard.set(downloadURL.absoluteString, forKey: Self.profileImageURLKey)
                
                // Sync profile (including new image URL) to Firestore
                uploadProfileToFirestore()
                
                logger.info("🔥 [ProfileSync] Profile image uploaded successfully")
            } catch {
                logger.error("🔥 [ProfileSync] Failed to upload profile image: \(error.localizedDescription)")
            }
        }
    }
    
    /// Download profile image from Firebase Storage URL and save locally.
    func downloadProfileImage(from urlString: String) {
        guard let url = URL(string: urlString) else { return }
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let image = UIImage(data: data) else {
                    logger.error("🔥 [ProfileSync] Downloaded data is not a valid image")
                    return
                }
                
                // Save to local Documents directory (same path ProfileView uses)
                await MainActor.run {
                    saveImageLocally(image)
                }
                
                logger.info("🔥 [ProfileSync] Profile image downloaded and saved locally")
            } catch {
                logger.error("🔥 [ProfileSync] Failed to download profile image: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Firestore Listener
    
    /// Whether we have completed the initial server fetch after sign-in.
    /// Until the server confirms no document exists, we must not upload empty
    /// local data (which would wipe cloud data on a fresh install).
    private var hasCompletedInitialFetch = false
    
    /// Key for caching Firestore permission denial
    private static let permDeniedKey = "firestorePermsDenied_profile"
    
    private func startFirestoreListener(userId: String) {
        guard firestoreListener == nil else {
            logger.debug("🔥 [ProfileSync] Firestore listener already active")
            return
        }
        
        logger.info("🔥 [ProfileSync] Starting Firestore profile sync for user \(userId)")
        
        let profileRef = db.collection("users").document(userId).collection("profile").document("data")
        
        // ── Step 1: Explicit server fetch on sign-in ──
        // On a fresh install the local Firestore cache is empty, so a snapshot
        // listener may briefly deliver an empty-cache result before the server
        // responds. An explicit server fetch ensures we get the real data first.
        hasCompletedInitialFetch = false
        
        profileRef.getDocument(source: .server) { [weak self] snapshot, error in
            guard let self = self else { return }
            
            Task { @MainActor in
                self.hasCompletedInitialFetch = true
                
                if let error = error {
                    if error.localizedDescription.contains("Missing or insufficient permissions") {
                        self.logger.info("🔥 [ProfileSync] Firestore permissions not configured — using local profile only")
                        UserDefaults.standard.set([
                            "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "",
                            "at": Date().timeIntervalSince1970
                        ], forKey: Self.permDeniedKey)
                    } else {
                        self.logger.error("🔥 [ProfileSync] Initial server fetch failed: \(error.localizedDescription)")
                    }
                } else if let snapshot = snapshot, snapshot.exists, let data = snapshot.data() {
                    UserDefaults.standard.removeObject(forKey: Self.permDeniedKey)
                    self.logger.info("🔥 [ProfileSync] Initial server fetch succeeded — restoring profile")
                    self.applyFirestoreSnapshot(data)
                } else {
                    UserDefaults.standard.removeObject(forKey: Self.permDeniedKey)
                    self.logger.info("🔥 [ProfileSync] No cloud profile on server, uploading local data")
                    self.uploadProfileToFirestore()
                }
            }
        }
        
        // ── Step 2: Real-time listener for ongoing changes ──
        firestoreListener = profileRef.addSnapshotListener { [weak self] snapshot, error in
            guard let self = self else { return }
            
            if let error = error {
                if error.localizedDescription.contains("Missing or insufficient permissions") {
                    self.logger.info("🔥 [ProfileSync] Firestore permissions not configured — using local profile only")
                    self.firestoreListener?.remove()
                    self.firestoreListener = nil
                    UserDefaults.standard.set([
                        "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "",
                        "at": Date().timeIntervalSince1970
                    ], forKey: Self.permDeniedKey)
                } else {
                    self.logger.error("🔥 [ProfileSync] Firestore listener error: \(error.localizedDescription)")
                }
                return
            }
            
            // Permission succeeded — clear any cached denial
            UserDefaults.standard.removeObject(forKey: Self.permDeniedKey)
            
            Task { @MainActor in
                self.isFirestoreSyncActive = true
                
                guard let snapshot = snapshot else { return }
                
                // Guard: Never upload empty local data based on a cached snapshot
                // before the initial server fetch completes.
                if !snapshot.exists {
                    if snapshot.metadata.isFromCache {
                        self.logger.debug("🔥 [ProfileSync] Ignoring empty cache snapshot (waiting for server)")
                        return
                    }
                    if !self.hasCompletedInitialFetch {
                        self.logger.debug("🔥 [ProfileSync] Waiting for initial server fetch before uploading")
                        return
                    }
                    self.logger.info("🔥 [ProfileSync] No cloud profile found (server confirmed), uploading local data")
                    self.uploadProfileToFirestore()
                    return
                }
                
                guard let data = snapshot.data() else { return }
                self.applyFirestoreSnapshot(data)
            }
        }
    }
    
    // MARK: - Apply Firestore Data Locally
    
    private func applyFirestoreSnapshot(_ data: [String: Any]) {
        isApplyingFirestoreUpdate = true
        defer { isApplyingFirestoreUpdate = false }
        
        let defaults = UserDefaults.standard
        
        // Only overwrite local values if Firestore has non-empty values
        if let name = data["displayName"] as? String, !name.isEmpty {
            let localName = defaults.string(forKey: Self.displayNameKey) ?? ""
            if localName.isEmpty || localName != name {
                defaults.set(name, forKey: Self.displayNameKey)
                logger.debug("🔥 [ProfileSync] Restored displayName: \(name)")
            }
        }
        
        if let bio = data["bio"] as? String {
            defaults.set(bio, forKey: Self.bioKey)
        }
        
        if let phone = data["phone"] as? String {
            defaults.set(phone, forKey: Self.phoneKey)
        }
        
        if let avatarPresetId = data["avatarPresetId"] as? String {
            defaults.set(avatarPresetId, forKey: Self.avatarPresetIdKey)
        }
        
        // If there's a cloud image URL and we don't have a local image, download it
        if let imageURL = data["profileImageURL"] as? String, !imageURL.isEmpty {
            let currentCloudURL = defaults.string(forKey: Self.profileImageURLKey) ?? ""
            defaults.set(imageURL, forKey: Self.profileImageURLKey)
            
            // Download image if URL changed or no local image exists
            if currentCloudURL != imageURL || !localProfileImageExists() {
                downloadProfileImage(from: imageURL)
            }
        }
        
        logger.info("🔥 [ProfileSync] Applied Firestore profile snapshot")
        
        // Force SwiftUI views using @AppStorage to re-read their values.
        // @AppStorage doesn't always detect external UserDefaults writes, so
        // we post a notification that interested views can observe.
        objectWillChange.send()
        NotificationCenter.default.post(name: .profileDidRestoreFromCloud, object: nil)
    }
    
    // MARK: - Upload to Firestore
    
    private func uploadProfileToFirestore() {
        guard !isApplyingFirestoreUpdate else { return }
        
        Task { @MainActor in
            guard AuthenticationManager.shared.isAuthenticated,
                  let userId = AuthenticationManager.shared.currentUser?.id else {
                return
            }
            
            let defaults = UserDefaults.standard
            
            var profileData: [String: Any] = [
                "displayName": defaults.string(forKey: Self.displayNameKey) ?? "",
                "bio": defaults.string(forKey: Self.bioKey) ?? "",
                "phone": defaults.string(forKey: Self.phoneKey) ?? "",
                "avatarPresetId": defaults.string(forKey: Self.avatarPresetIdKey) ?? "",
                "updatedAt": FieldValue.serverTimestamp()
            ]
            
            // Include cloud image URL if available
            if let cloudURL = defaults.string(forKey: Self.profileImageURLKey), !cloudURL.isEmpty {
                profileData["profileImageURL"] = cloudURL
            }
            
            let profileRef = db.collection("users").document(userId).collection("profile").document("data")
            
            do {
                try await profileRef.setData(profileData, merge: true)
                logger.debug("🔥 [ProfileSync] Profile synced to Firestore successfully")
            } catch {
                logger.error("🔥 [ProfileSync] Failed to sync profile to Firestore: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Local Image Helpers
    
    private func localProfileImageExists() -> Bool {
        guard let url = localProfileImageURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    private var localProfileImageURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("profile_image.jpg")
    }
    
    private func saveImageLocally(_ image: UIImage) {
        guard let url = localProfileImageURL,
              let data = image.jpegData(compressionQuality: 0.8) else { return }
        
        do {
            try data.write(to: url)
            UserDefaults.standard.set(url.path, forKey: Self.imagePathKey)
            logger.debug("🔥 [ProfileSync] Saved profile image locally at \(url.path)")
            
            // Notify views that the profile image was restored
            NotificationCenter.default.post(name: .profileDidRestoreFromCloud, object: nil)
        } catch {
            logger.error("🔥 [ProfileSync] Failed to save profile image locally: \(error.localizedDescription)")
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted after ProfileSyncService applies Firestore data to local storage.
    /// Views using @AppStorage for profile fields should observe this to force
    /// a refresh, since @AppStorage doesn't always detect external UserDefaults writes.
    static let profileDidRestoreFromCloud = Notification.Name("ProfileDidRestoreFromCloud")
}
