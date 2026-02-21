//
//  EditProfileView.swift
//  CryptoSage
//
//  Profile editing view for creating or updating user profiles.
//  Integrates with ProfileSyncManager for bidirectional sync with Settings.
//

import SwiftUI

struct EditProfileView: View {
    var isNewProfile: Bool = false
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var socialService = SocialService.shared
    @StateObject private var liveTracker = LivePerformanceTracker.shared
    @ObservedObject private var profileSyncManager = ProfileSyncManager.shared
    
    @State private var username = ""
    @State private var displayName = ""
    @State private var bio = ""
    @State private var avatarPresetId: String? = nil
    @State private var isPublic = true
    @State private var showOnLeaderboard = false
    @State private var leaderboardMode: LeaderboardParticipationMode = .none
    @State private var liveTrackingConsent = false
    @State private var primaryTradingMode: UserTradingMode = .paper
    @State private var twitter = ""
    @State private var telegram = ""
    @State private var isSaving = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var didPreFill = false
    @State private var showAvatarPicker = false
    @State private var showLiveConsentSheet = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // Avatar with edit functionality
                    HStack {
                        Spacer()
                        
                        EditableAvatarView(
                            username: username.isEmpty ? "User" : username,
                            avatarPresetId: avatarPresetId,
                            size: 80
                        ) {
                            showAvatarPicker = true
                        }
                        
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                    
                    // Change Avatar button
                    Button {
                        showAvatarPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "photo.circle.fill")
                                .foregroundColor(.accentColor)
                            Text("Change Avatar")
                                .foregroundColor(.primary)
                        }
                    }
                }
                
                Section {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Required")
                } footer: {
                    HStack(spacing: 6) {
                        Image(systemName: "globe")
                            .font(.caption2)
                        Text("This is your public identity on leaderboards. Only your @username will be shown.")
                    }
                    .foregroundStyle(.secondary)
                }
                
                Section {
                    TextField("Display Name", text: $displayName)
                    
                    TextField("Bio", text: $bio, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Optional")
                } footer: {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                        Text("Display name and bio are only visible on your profile page, not on leaderboards.")
                    }
                    .foregroundStyle(.secondary)
                }
                
                Section("Privacy") {
                    Toggle("Public Profile", isOn: $isPublic)
                    
                    if !isPublic {
                        Text("Others cannot view your profile page")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section {
                    Toggle(isOn: $showOnLeaderboard) {
                        HStack(spacing: 12) {
                            Image(systemName: "trophy.fill")
                                .foregroundStyle(.yellow)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Show on Leaderboard")
                                Text("Compete with other traders")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onChange(of: showOnLeaderboard) { oldValue, newValue in
                        if newValue && leaderboardMode == .none {
                            leaderboardMode = .paperOnly
                        } else if !newValue {
                            leaderboardMode = .none
                        }
                    }
                    
                    if showOnLeaderboard {
                        // Leaderboard Participation Mode Picker
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Competition Mode")
                                .font(.subheadline.weight(.medium))
                            
                            ForEach(LeaderboardParticipationMode.allCases.filter { $0 != .none }, id: \.self) { mode in
                                leaderboardModeRow(mode)
                            }
                        }
                        .padding(.vertical, 4)
                        
                        // Live Trading Consent (if applicable)
                        if leaderboardMode == .liveOnly || leaderboardMode == .both {
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle(isOn: $liveTrackingConsent) {
                                    HStack(spacing: 10) {
                                        Image(systemName: "checkmark.seal.fill")
                                            .foregroundStyle(.green)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Enable Live Tracking")
                                            Text("Track portfolio performance for leaderboard")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .onChange(of: liveTrackingConsent) { oldValue, newValue in
                                    if newValue && !liveTracker.hasConsent {
                                        showLiveConsentSheet = true
                                    } else if !newValue && liveTracker.hasConsent {
                                        liveTracker.revokeConsent()
                                    }
                                }
                                
                                if !liveTrackingConsent && (leaderboardMode == .liveOnly || leaderboardMode == .both) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundStyle(.orange)
                                            .font(.caption)
                                        
                                        Text("Portfolio tracking consent required to compete in Portfolio leaderboard")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        
                        // Privacy notice
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lock.shield.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                            
                            Text("Only your username and aggregated stats (PnL %, win rate) are shown. Individual trades are never shared.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Leaderboard")
                } footer: {
                    if !showOnLeaderboard {
                        Text("Enable to compete with other traders and track your rank")
                    }
                }
                
                Section("Social Links") {
                    HStack {
                        Image(systemName: "at")
                            .foregroundStyle(.secondary)
                        TextField("Twitter handle", text: $twitter)
                            .textInputAutocapitalization(.never)
                    }
                    
                    HStack {
                        Image(systemName: "paperplane.fill")
                            .foregroundStyle(.secondary)
                        TextField("Telegram username", text: $telegram)
                            .textInputAutocapitalization(.never)
                    }
                }
            }
            .navigationTitle(isNewProfile ? "Create Profile" : "Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    CSNavButton(
                        icon: "xmark",
                        action: { dismiss() },
                        accessibilityText: "Close",
                        accessibilityHintText: "Dismiss profile editor"
                    )
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        saveProfile()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(
                                            colorScheme == .dark
                                                ? AnyShapeStyle(BrandColors.goldHorizontal)
                                                : AnyShapeStyle(BrandColors.goldBase)
                                        )
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(username.isEmpty || isSaving)
                }
            }
            .toolbarBackground(DS.Adaptive.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showAvatarPicker) {
                AvatarPickerView(
                    username: username.isEmpty ? "User" : username,
                    selectedAvatarId: $avatarPresetId
                )
            }
            .sheet(isPresented: $showLiveConsentSheet) {
                LiveTrackingConsentView { granted in
                    liveTrackingConsent = granted
                    if !granted && leaderboardMode == .liveOnly {
                        leaderboardMode = .paperOnly
                    } else if !granted && leaderboardMode == .both {
                        leaderboardMode = .paperOnly
                    }
                }
            }
            .onAppear {
                loadExistingProfile()
                liveTrackingConsent = liveTracker.hasConsent
            }
        }
    }
    
    // MARK: - Leaderboard Mode Row
    
    private func leaderboardModeRow(_ mode: LeaderboardParticipationMode) -> some View {
        Button {
            leaderboardMode = mode
            
            // Set primary trading mode based on selection
            switch mode {
            case .paperOnly:
                primaryTradingMode = .paper
            case .liveOnly:
                primaryTradingMode = .portfolio
            case .both:
                // Keep current or default to paper
                break
            case .none:
                break
            }
            
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: mode.icon)
                    .font(.title3)
                    .foregroundStyle(iconColor(for: mode))
                    .frame(width: 28)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    
                    Text(mode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                if leaderboardMode == mode {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(leaderboardMode == mode 
                        ? iconColor(for: mode).opacity(0.1)
                        : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(leaderboardMode == mode 
                        ? iconColor(for: mode).opacity(0.5)
                        : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private func iconColor(for mode: LeaderboardParticipationMode) -> Color {
        switch mode {
        case .none: return .gray
        case .paperOnly: return AppTradingMode.paper.color
        case .liveOnly: return .green
        case .both: return .yellow
        }
    }
    
    private func loadExistingProfile() {
        // If editing existing profile, load from Social service
        if let profile = socialService.currentProfile {
            username = profile.username
            displayName = profile.displayName ?? ""
            bio = profile.bio ?? ""
            avatarPresetId = profile.avatarPresetId
            isPublic = profile.isPublic
            showOnLeaderboard = profile.showOnLeaderboard
            leaderboardMode = profile.leaderboardMode
            liveTrackingConsent = profile.liveTrackingConsent
            primaryTradingMode = profile.primaryTradingMode
            twitter = profile.socialLinks?.twitter ?? ""
            telegram = profile.socialLinks?.telegram ?? ""
            didPreFill = true
            return
        }
        
        // For new profile, pre-fill from Settings profile data if available
        if isNewProfile && !didPreFill {
            let settingsData = profileSyncManager.getSettingsProfileData()
            if !settingsData.displayName.isEmpty {
                displayName = settingsData.displayName
                // Generate a suggested username from display name
                let suggestedUsername = settingsData.displayName
                    .lowercased()
                    .replacingOccurrences(of: " ", with: "_")
                    .replacingOccurrences(of: "[^a-z0-9_]", with: "", options: .regularExpression)
                if username.isEmpty {
                    username = suggestedUsername
                }
            }
            if !settingsData.bio.isEmpty {
                bio = settingsData.bio
            }
            
            // Generate a username if none exists
            if username.isEmpty {
                username = UsernameGenerator.generate().lowercased()
            }
            
            didPreFill = true
        }
    }
    
    private func saveProfile() {
        guard !username.isEmpty else { return }
        
        // Validate username
        let validUsername = username.lowercased().replacingOccurrences(of: " ", with: "_")
        
        isSaving = true
        
        Task {
            do {
                let socialLinks = SocialLinks(
                    twitter: twitter.isEmpty ? nil : twitter,
                    telegram: telegram.isEmpty ? nil : telegram
                )
                
                try await socialService.createOrUpdateProfile(
                    username: validUsername,
                    displayName: displayName.isEmpty ? nil : displayName,
                    avatarPresetId: avatarPresetId,
                    bio: bio.isEmpty ? nil : bio,
                    isPublic: isPublic,
                    showOnLeaderboard: showOnLeaderboard,
                    leaderboardMode: leaderboardMode,
                    liveTrackingConsent: liveTrackingConsent,
                    primaryTradingMode: primaryTradingMode,
                    socialLinks: socialLinks
                )
                
                // Update live tracker consent
                if liveTrackingConsent && !liveTracker.hasConsent {
                    liveTracker.grantConsent()
                } else if !liveTrackingConsent && liveTracker.hasConsent {
                    liveTracker.revokeConsent()
                }
                
                // Trigger bidirectional sync with Settings profile
                profileSyncManager.syncSocialToSettings()
                
                await MainActor.run {
                    isSaving = false
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                    showingError = true
                }
            }
        }
    }
}

#Preview {
    EditProfileView(isNewProfile: true)
}
