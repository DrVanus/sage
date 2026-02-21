//
//  ProfileSyncManager.swift
//  CryptoSage
//
//  Bidirectional sync manager between Settings profile (AppStorage) and
//  Social profile (SocialService). Ensures profile data stays consistent
//  across both systems.
//

import Foundation
import SwiftUI
import Combine

/// Manages bidirectional synchronization between the Settings profile (AppStorage)
/// and the Social profile (SocialService.currentProfile).
@MainActor
public final class ProfileSyncManager: ObservableObject {
    public static let shared = ProfileSyncManager()
    
    // MARK: - AppStorage Keys (mirrored from SettingsView)
    // Empty defaults - will be populated by AuthenticationManager on sign-in
    
    @AppStorage("profile.displayName") private var settingsDisplayName: String = ""
    @AppStorage("profile.bio") private var settingsBio: String = ""
    @AppStorage("profile.email") private var settingsEmail: String = ""
    @AppStorage("profile.phone") private var settingsPhone: String = ""
    
    // Social-specific fields stored in AppStorage for convenience
    @AppStorage("profile.username") private var socialUsername: String = ""
    @AppStorage("profile.twitter") private var socialTwitter: String = ""
    @AppStorage("profile.telegram") private var socialTelegram: String = ""
    @AppStorage("profile.isPublic") private var socialIsPublic: Bool = true
    @AppStorage("profile.showOnLeaderboard") private var socialShowOnLeaderboard: Bool = false
    
    // MARK: - State
    
    @Published public private(set) var isSyncing = false
    @Published public private(set) var lastSyncDate: Date?
    
    private var cancellables = Set<AnyCancellable>()
    private var isSyncInProgress = false
    
    // MARK: - Initialization
    
    private init() {
        setupObservers()
        
        // Initial sync on launch - prefer Social profile if it exists
        Task {
            await performInitialSync()
        }
    }
    
    // MARK: - Setup
    
    private func setupObservers() {
        // Observe SocialService profile changes
        SocialService.shared.$currentProfile
            .dropFirst() // Skip initial value
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] profile in
                guard let self = self, !self.isSyncInProgress else { return }
                Task { @MainActor in
                    self.syncFromSocialToSettings(profile)
                }
            }
            .store(in: &cancellables)
        
        // Observe AppStorage changes via NotificationCenter
        // UserDefaults posts notifications when values change
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self, !self.isSyncInProgress else { return }
                Task { @MainActor in
                    await self.syncFromSettingsToSocial()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Initial Sync
    
    private func performInitialSync() async {
        guard !isSyncInProgress else { return }
        isSyncInProgress = true
        isSyncing = true
        
        defer {
            isSyncInProgress = false
            isSyncing = false
            lastSyncDate = Date()
        }
        
        // If Social profile exists, it takes precedence
        if let socialProfile = SocialService.shared.currentProfile {
            applySocialToSettings(socialProfile)
        } else if !settingsDisplayName.isEmpty {
            // Settings has custom data but no Social profile - sync to Social
            await applySettingsToSocial()
        }
    }
    
    // MARK: - Sync: Social -> Settings
    
    /// Syncs data from SocialService profile to AppStorage (Settings)
    /// Called from observer — acquires sync lock
    private func syncFromSocialToSettings(_ profile: UserProfile?) {
        guard let profile = profile else { return }
        guard !isSyncInProgress else { return }
        
        isSyncInProgress = true
        isSyncing = true
        
        defer {
            isSyncInProgress = false
            isSyncing = false
            lastSyncDate = Date()
        }
        
        applySocialToSettings(profile)
    }
    
    /// Core sync logic: Social -> Settings (does NOT manage the sync lock)
    private func applySocialToSettings(_ profile: UserProfile) {
        // Sync display name (only sync if Social profile has an explicit displayName)
        // Do NOT auto-promote the auto-generated username to display name, as it
        // causes confusing initials (e.g. "S" from "Steelgazelle") on the avatar.
        if let displayName = profile.displayName, !displayName.isEmpty {
            if settingsDisplayName != displayName {
                settingsDisplayName = displayName
            }
        }
        
        // Sync bio
        if let bio = profile.bio, !bio.isEmpty {
            if settingsBio != bio {
                settingsBio = bio
            }
        }
        
        // Sync avatar preset — ensures Settings ProfileView and Social profile show the same avatar
        if let presetId = profile.avatarPresetId {
            let currentPreset = UserDefaults.standard.string(forKey: "profile.avatarPresetId") ?? ""
            if currentPreset != presetId {
                UserDefaults.standard.set(presetId, forKey: "profile.avatarPresetId")
            }
        }
        
        // Sync social-specific fields to AppStorage
        if !profile.username.isEmpty && socialUsername != profile.username {
            socialUsername = profile.username
        }
        
        if let twitter = profile.socialLinks?.twitter, socialTwitter != twitter {
            socialTwitter = twitter
        }
        
        if let telegram = profile.socialLinks?.telegram, socialTelegram != telegram {
            socialTelegram = telegram
        }
        
        if socialIsPublic != profile.isPublic {
            socialIsPublic = profile.isPublic
        }
        
        if socialShowOnLeaderboard != profile.showOnLeaderboard {
            socialShowOnLeaderboard = profile.showOnLeaderboard
        }
        
        DebugLog.log("ProfileSync", "Synced from Social to Settings: \(profile.username)")
    }
    
    // MARK: - Sync: Settings -> Social
    
    /// Syncs data from AppStorage (Settings) to SocialService profile
    /// Called from observer — acquires sync lock
    private func syncFromSettingsToSocial() async {
        guard !isSyncInProgress else { return }
        
        isSyncInProgress = true
        isSyncing = true
        
        defer {
            isSyncInProgress = false
            isSyncing = false
            lastSyncDate = Date()
        }
        
        await applySettingsToSocial()
    }
    
    /// Core sync logic: Settings -> Social (does NOT manage the sync lock)
    private func applySettingsToSocial() async {
        // Only sync if there's meaningful data in Settings
        guard !settingsDisplayName.isEmpty || !settingsBio.isEmpty else { return }
        
        // Check if Social profile exists
        guard let currentProfile = SocialService.shared.currentProfile else {
            // No Social profile yet - don't auto-create, user must explicitly create via Social tab
            return
        }
        
        // Check if sync is needed
        let needsSync = (currentProfile.displayName != settingsDisplayName && !settingsDisplayName.isEmpty) ||
                        (currentProfile.bio != settingsBio && !settingsBio.isEmpty)
        
        guard needsSync else { return }
        
        do {
            // Update Social profile with Settings data
            let newDisplayName = !settingsDisplayName.isEmpty ? settingsDisplayName : currentProfile.displayName
            let newBio = !settingsBio.isEmpty ? settingsBio : currentProfile.bio
            
            try await SocialService.shared.createOrUpdateProfile(
                username: currentProfile.username,
                displayName: newDisplayName,
                avatarPresetId: currentProfile.avatarPresetId,
                bio: newBio,
                isPublic: currentProfile.isPublic,
                showOnLeaderboard: currentProfile.showOnLeaderboard,
                leaderboardMode: currentProfile.leaderboardMode,
                liveTrackingConsent: currentProfile.liveTrackingConsent,
                primaryTradingMode: currentProfile.primaryTradingMode,
                socialLinks: currentProfile.socialLinks
            )
            
            DebugLog.log("ProfileSync", "Synced from Settings to Social")
        } catch {
            DebugLog.error("[ProfileSync] Error syncing to Social: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Public API
    
    /// Manually trigger a sync from Social to Settings
    public func syncSocialToSettings() {
        guard let profile = SocialService.shared.currentProfile else { return }
        syncFromSocialToSettings(profile)
    }
    
    /// Manually trigger a sync from Settings to Social
    public func syncSettingsToSocial() async {
        await syncFromSettingsToSocial()
    }
    
    /// Force a full bidirectional sync
    public func forceSync() async {
        await performInitialSync()
    }
    
    /// Pre-fill Social profile creation form with Settings data
    public func getSettingsProfileData() -> (displayName: String, bio: String) {
        return (displayName: settingsDisplayName, bio: settingsBio)
    }
    
    /// Check if Settings has profile data that could be used to pre-fill Social
    public var hasSettingsProfileData: Bool {
        !settingsDisplayName.isEmpty || !settingsBio.isEmpty
    }
    
    /// The current social username (if set)
    public var currentUsername: String? {
        let username = socialUsername
        return username.isEmpty ? nil : username
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let profileDidSync = Notification.Name("ProfileDidSync")
}
