//
//  ProfileView.swift
//  CryptoSage
//
//  User profile management view with personal information,
//  account details, and profile customization.
//

import SwiftUI
import AuthenticationServices
import FirebaseAuth

// MARK: - Profile View

struct ProfileView: View {
    @Environment(\.dismiss) private var dismiss
    
    // Auth state - observe for real-time updates
    @ObservedObject private var authManager = AuthenticationManager.shared
    
    // Observe ProfileSyncService so the view re-renders when cloud data is restored.
    // This ensures @AppStorage values below are re-read after Firestore sync.
    @ObservedObject private var profileSync = ProfileSyncService.shared
    
    // User profile data (stored in UserDefaults for persistence)
    // Empty defaults - will be populated by AuthenticationManager on sign-in
    @AppStorage("profile.displayName") private var displayName: String = ""
    @AppStorage("profile.email") private var email: String = ""
    @AppStorage("profile.phone") private var phone: String = ""
    @AppStorage("profile.bio") private var bio: String = ""
    @AppStorage("profile.imagePath") private var profileImagePath: String = ""
    
    // Social avatar preset — synced from social profile when user picks an icon
    @AppStorage("profile.avatarPresetId") private var avatarPresetId: String = ""
    
    // Subscription state for dynamic plan display
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    
    @Environment(\.colorScheme) private var colorScheme
    
    // Sign-out alert state (moved from Settings)
    @State private var showSignOutAlert = false
    
    /// Effective display name - auth data takes priority
    private var effectiveDisplayName: String {
        if let authName = authManager.currentUser?.displayName, !authName.isEmpty {
            return authName
        }
        return displayName.isEmpty ? "CryptoSage User" : displayName
    }
    
    /// Effective email - auth data takes priority
    private var effectiveEmail: String {
        if let authEmail = authManager.currentUser?.email, !authEmail.isEmpty {
            return authEmail
        }
        return email.isEmpty ? "Not set" : email
    }
    
    /// Detect the primary authentication provider for the current user
    private var authProviderName: String? {
        guard let providerData = Auth.auth().currentUser?.providerData else { return nil }
        if providerData.contains(where: { $0.providerID == "apple.com" }) {
            return "Apple"
        } else if providerData.contains(where: { $0.providerID == "google.com" }) {
            return "Google"
        } else if providerData.contains(where: { $0.providerID == "password" }) {
            return "Email"
        }
        return nil
    }
    
    /// Whether the current user signed in with email/password (which allows email changes)
    private var isEmailPasswordUser: Bool {
        Auth.auth().currentUser?.providerData.contains(where: { $0.providerID == "password" }) ?? false
    }
    
    /// Profile subtitle shown under the avatar
    private var profileSubtitle: String {
        if authManager.isAuthenticated {
            if let authEmail = authManager.currentUser?.email, !authEmail.isEmpty {
                return authEmail
            }
            return "Signed in with Apple"
        }
        // When not authenticated, prompt to sign in
        return "Sign in to sync across devices"
    }
    
    /// Dynamic plan display name that respects developer mode
    private var planDisplayName: String {
        let tier = subscriptionManager.effectiveTier
        if subscriptionManager.isDeveloperMode {
            return "\(tier.displayName) (Dev)"
        }
        return "\(tier.displayName) Plan"
    }
    
    /// Color for the tier badge
    private var tierColor: Color {
        switch subscriptionManager.effectiveTier {
        case .free: return BrandColors.goldBase
        case .pro: return BrandColors.goldBase
        case .premium: return .purple
        }
    }
    
    @State private var isEditingName = false
    @State private var isEditingPhone = false
    @State private var isEditingBio = false
    @State private var tempValue: String = ""
    @State private var showImagePicker = false
    @State private var showAvatarPicker = false
    @State private var showAuthOptions = false
    @State private var showEmailChangeSheet = false
    @State private var emailChangePassword: String = ""
    @State private var emailChangeNew: String = ""
    @State private var emailChangeError: String? = nil
    @State private var emailChangeLoading = false
    @State private var profileImage: UIImage? = nil
    
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let selectionFeedback = UISelectionFeedbackGenerator()
    
    var body: some View {
        VStack(spacing: 0) {
            // Custom Header
            profileHeader
            
            ScrollView {
                VStack(spacing: 20) {
                    // MARK: - Sign In Card (shown when not authenticated)
                    if !authManager.isAuthenticated {
                        profileSignInCard
                            .padding(.top, 16)
                    }
                    
                    // Profile Avatar Section
                    profileAvatarSection
                        .padding(.top, authManager.isAuthenticated ? 20 : 8)
                    
                    // Personal Info Section
                    ProfileSection(title: "PERSONAL INFORMATION") {
                        ProfileEditableRow(
                            icon: "person.fill",
                            title: "Display Name",
                            value: effectiveDisplayName,
                            isEditing: $isEditingName,
                            tempValue: $tempValue,
                            onSave: {
                                displayName = tempValue
                                // Propagate name to Firebase Auth + Firestore
                                AuthenticationManager.shared.updateDisplayName(tempValue)
                                ProfileSyncService.shared.syncProfileToFirestore()
                            }
                        )
                        ProfileDivider()
                        // Email row — auth-aware behavior
                        emailRow
                        ProfileDivider()
                        ProfileEditableRow(
                            icon: "phone.fill",
                            title: "Phone",
                            value: phone.isEmpty ? "Not set" : phone,
                            isEditing: $isEditingPhone,
                            tempValue: $tempValue,
                            onSave: {
                                phone = tempValue
                                ProfileSyncService.shared.syncProfileToFirestore()
                            },
                            keyboardType: .phonePad
                        )
                    }
                    
                    // Bio Section
                    ProfileSection(title: "ABOUT") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(BrandColors.goldBase.opacity(0.12))
                                        .frame(width: 30, height: 30)
                                    Image(systemName: "text.quote")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(BrandColors.goldBase)
                                }
                                Text("Bio")
                                    .font(.body)
                                    .foregroundColor(DS.Adaptive.textPrimary)
                                Spacer()
                                Button(action: {
                                    impactLight.impactOccurred()
                                    tempValue = bio
                                    isEditingBio = true
                                }) {
                                    Text(bio.isEmpty ? "Add" : "Edit")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(BrandColors.goldBase)
                                }
                            }
                            if !bio.isEmpty {
                                Text(bio)
                                    .font(.subheadline)
                                    .foregroundColor(DS.Adaptive.textSecondary)
                                    .padding(.leading, 42)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    
                    // Account Info Section
                    ProfileSection(title: "ACCOUNT") {
                        ProfileInfoRow(
                            icon: "calendar",
                            title: "Member Since",
                            value: authManager.currentUser.map { formatMemberDate($0.createdAt) } ?? "Not signed in"
                        )
                        ProfileDivider()
                        NavigationLink(destination: SubscriptionPricingView()) {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(BrandColors.goldBase.opacity(0.12))
                                        .frame(width: 30, height: 30)
                                    Image(systemName: "star.fill")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(BrandColors.goldBase)
                                }
                                Text("Plan")
                                    .font(.body)
                                    .foregroundColor(DS.Adaptive.textPrimary)
                                Spacer()
                                Text(planDisplayName)
                                    .font(.subheadline)
                                    .foregroundColor(tierColor)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(DS.Adaptive.textTertiary)
                            }
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                        ProfileDivider()
                        if authManager.isAuthenticated {
                            let firebaseUser = Auth.auth().currentUser
                            let isEmailVerified = firebaseUser?.isEmailVerified ?? false
                            let isAppleOrGoogle = firebaseUser?.providerData.contains(where: {
                                $0.providerID == "apple.com" || $0.providerID == "google.com"
                            }) ?? false
                            let verified = isEmailVerified || isAppleOrGoogle
                            
                            if verified {
                                ProfileInfoRow(
                                    icon: "checkmark.shield.fill",
                                    title: "Verified",
                                    value: "Verified",
                                    valueColor: .green
                                )
                            } else {
                                Button(action: {
                                    Task {
                                        try? await authManager.sendEmailVerification()
                                    }
                                }) {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .fill(Color.orange.opacity(0.12))
                                                .frame(width: 30, height: 30)
                                            Image(systemName: "exclamationmark.shield.fill")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(.orange)
                                        }
                                        Text("Verified")
                                            .font(.body)
                                            .foregroundColor(DS.Adaptive.textPrimary)
                                        Spacer()
                                        Text("Tap to resend verification")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                    .padding(.vertical, 5)
                                }
                                .buttonStyle(.plain)
                            }
                        } else {
                            Button(action: {
                                impactLight.impactOccurred()
                                showAuthOptions = true
                            }) {
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(BrandColors.goldBase.opacity(0.12))
                                            .frame(width: 30, height: 30)
                                        Image(systemName: "checkmark.shield.fill")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(BrandColors.goldBase)
                                    }
                                    Text("Verified")
                                        .font(.body)
                                        .foregroundColor(DS.Adaptive.textPrimary)
                                    Spacer()
                                    Text("Sign in to verify")
                                        .font(.subheadline)
                                        .foregroundColor(DS.Adaptive.textTertiary)
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(DS.Adaptive.textTertiary)
                                }
                                .padding(.vertical, 5)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    // Account Actions
                    ProfileSection(title: "ACCOUNT ACTIONS") {
                        Button(action: {
                            impactLight.impactOccurred()
                            // Clear custom profile data (but keep auth-synced data)
                            phone = ""
                            bio = ""
                            profileImage = nil
                            deleteProfileImage()
                            // Only clear name/email if not authenticated
                            if !authManager.isAuthenticated {
                                displayName = ""
                                email = ""
                            }
                        }) {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(Color.orange.opacity(0.12))
                                        .frame(width: 30, height: 30)
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.orange)
                                }
                                Text("Clear Custom Data")
                                    .font(.body)
                                    .foregroundColor(.orange)
                                Spacer()
                            }
                            .padding(.vertical, 5)
                        }
                        
                        // Sign Out (only when authenticated)
                        if authManager.isAuthenticated {
                            ProfileDivider()
                            Button(action: {
                                impactLight.impactOccurred()
                                showSignOutAlert = true
                            }) {
                                HStack(spacing: 12) {
                                    ZStack {
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(Color.red.opacity(0.12))
                                            .frame(width: 30, height: 30)
                                        Image(systemName: "rectangle.portrait.and.arrow.right")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.red)
                                    }
                                    Text("Sign Out")
                                        .font(.body)
                                        .foregroundColor(.red)
                                    Spacer()
                                }
                                .padding(.vertical, 5)
                            }
                        }
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 16)
            }
            .scrollViewBackSwipeFix()
        }
        .background(DS.Adaptive.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
        .alert("Sign Out", isPresented: $showSignOutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                AuthenticationManager.shared.signOut()
                dismiss()
            }
        } message: {
            Text("Are you sure you want to sign out? Your local data will remain on this device.")
        }
        .sheet(isPresented: $isEditingBio) {
            ProfileBioEditor(bio: $bio, tempValue: $tempValue, isPresented: $isEditingBio)
        }
        .sheet(isPresented: $showAuthOptions) {
            AuthOptionsView()
        }
        .sheet(isPresented: $showImagePicker) {
            ProfileImagePicker(image: $profileImage, onImageSelected: saveProfileImage)
        }
        .sheet(isPresented: $showAvatarPicker) {
            NavigationStack {
                AvatarPickerView(
                    username: effectiveDisplayName,
                    selectedAvatarId: Binding(
                        get: { avatarPresetId.isEmpty ? nil : avatarPresetId },
                        set: { newValue in
                            avatarPresetId = newValue ?? ""
                            // Also sync to social profile if one exists
                            if let profile = SocialService.shared.currentProfile {
                                Task {
                                    try? await SocialService.shared.createOrUpdateProfile(
                                        username: profile.username,
                                        displayName: profile.displayName,
                                        avatarPresetId: newValue,
                                        bio: profile.bio,
                                        isPublic: profile.isPublic,
                                        showOnLeaderboard: profile.showOnLeaderboard,
                                        leaderboardMode: profile.leaderboardMode,
                                        liveTrackingConsent: profile.liveTrackingConsent,
                                        primaryTradingMode: profile.primaryTradingMode,
                                        socialLinks: profile.socialLinks
                                    )
                                }
                            }
                            // Clear custom photo when user picks an avatar icon
                            if newValue != nil {
                                profileImage = nil
                                deleteProfileImage()
                            }
                            // Sync avatar change to Firestore
                            ProfileSyncService.shared.syncProfileToFirestore()
                        }
                    )
                )
            }
        }
        .onAppear {
            loadProfileImage()
        }
    }
    
    // MARK: - Email Row (auth-aware)
    
    @ViewBuilder
    private var emailRow: some View {
        if authManager.isAuthenticated {
            // Signed in — show email from auth provider, read-only for Apple/Google
            let providerLabel = authProviderName ?? "Account"
            let emailValue = effectiveEmail
            
            if isEmailPasswordUser {
                // Email/Password user — allow changing email (requires re-authentication)
                Button {
                    impactLight.impactOccurred()
                    emailChangeNew = ""
                    emailChangePassword = ""
                    emailChangeError = nil
                    showEmailChangeSheet = true
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(BrandColors.goldBase.opacity(0.12))
                                .frame(width: 30, height: 30)
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(BrandColors.goldBase)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Email")
                                .font(.caption)
                                .foregroundColor(DS.Adaptive.textTertiary)
                            Text(emailValue)
                                .font(.body)
                                .foregroundColor(DS.Adaptive.textPrimary)
                        }
                        
                        Spacer()
                        
                        Text("Change")
                            .font(.caption.weight(.medium))
                            .foregroundColor(BrandColors.goldBase)
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(DS.Adaptive.textTertiary)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showEmailChangeSheet) {
                    emailChangeSheetContent
                }
            } else {
                // Apple or Google user — email is read-only (managed by provider)
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(BrandColors.goldBase.opacity(0.12))
                            .frame(width: 30, height: 30)
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(BrandColors.goldBase)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Email")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Text(emailValue)
                            .font(.body)
                            .foregroundColor(DS.Adaptive.textPrimary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11))
                        Text("via \(providerLabel)")
                            .font(.caption)
                    }
                    .foregroundColor(DS.Adaptive.textTertiary)
                }
                .padding(.vertical, 6)
            }
        } else {
            // Not signed in — tapping the row opens auth sheet
            VStack(spacing: 10) {
                // Email info row
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(BrandColors.goldBase.opacity(0.12))
                            .frame(width: 30, height: 30)
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(BrandColors.goldBase)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Email")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textTertiary)
                        Text("Sign in to set email")
                            .font(.body)
                            .foregroundColor(DS.Adaptive.textSecondary)
                    }
                    
                    Spacer()
                    
                    // Gold pill CTA
                    Button {
                        impactLight.impactOccurred()
                        showAuthOptions = true
                    } label: {
                        Text("Sign In")
                            .font(.caption.weight(.bold))
                    }
                    .buttonStyle(
                        PremiumCompactCTAStyle(
                            height: 28,
                            horizontalPadding: 12,
                            cornerRadius: 14,
                            font: .caption.weight(.bold)
                        )
                    )
                }
                .padding(.vertical, 6)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                impactLight.impactOccurred()
                showAuthOptions = true
            }
            .accessibilityLabel("Sign in to set your email address")
        }
    }
    
    // MARK: - Email Change Sheet (for email/password users)
    
    private var emailChangeSheetContent: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("To change your email, please verify your current password first.")
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("New Email")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textTertiary)
                        TextField("new@example.com", text: $emailChangeNew)
                            .textFieldStyle(.plain)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(BrandColors.goldBase.opacity(0.3), lineWidth: 1)
                            )
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Current Password")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textTertiary)
                        SecureField("Enter your password", text: $emailChangePassword)
                            .textFieldStyle(.plain)
                            .textContentType(.password)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(BrandColors.goldBase.opacity(0.3), lineWidth: 1)
                            )
                    }
                }
                .padding(.horizontal, 20)
                
                if let error = emailChangeError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                
                Button {
                    Task { await changeEmail() }
                } label: {
                    HStack {
                        if emailChangeLoading {
                            ProgressView()
                                .tint(colorScheme == .dark ? .black : .white)
                        } else {
                            Text("Update Email")
                                .font(.headline.weight(.bold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundColor(colorScheme == .dark ? .black : .white)
                    .background(
                        Capsule().fill(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [BrandColors.goldLight, BrandColors.goldBase]
                                    : [BrandColors.goldBase, BrandColors.goldDark],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    )
                }
                .disabled(emailChangeNew.isEmpty || emailChangePassword.isEmpty || emailChangeLoading)
                .opacity((emailChangeNew.isEmpty || emailChangePassword.isEmpty) ? 0.5 : 1)
                .padding(.horizontal, 20)
                
                Text("A verification link will be sent to your new email address.")
                    .font(.caption2)
                    .foregroundColor(DS.Adaptive.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                
                Spacer()
            }
            .navigationTitle("Change Email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { showEmailChangeSheet = false } label: {
                        Text("Cancel")
                            .foregroundStyle(DS.Adaptive.textSecondary)
                    }
                }
            }
            .toolbarBackground(DS.Adaptive.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
    
    // MARK: - Change Email Action
    
    private func changeEmail() async {
        emailChangeLoading = true
        emailChangeError = nil
        
        guard let currentUser = Auth.auth().currentUser,
              let currentEmail = currentUser.email else {
            emailChangeError = "Unable to find current account."
            emailChangeLoading = false
            return
        }
        
        // Validate new email format
        let emailRegex = /^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$/
        guard emailChangeNew.wholeMatch(of: emailRegex) != nil else {
            emailChangeError = "Please enter a valid email address."
            emailChangeLoading = false
            return
        }
        
        do {
            // Step 1: Re-authenticate with current password
            let credential = EmailAuthProvider.credential(
                withEmail: currentEmail,
                password: emailChangePassword
            )
            try await currentUser.reauthenticate(with: credential)
            
            // Step 2: Send verification to new email (Firebase sends a link)
            try await currentUser.sendEmailVerification(beforeUpdatingEmail: emailChangeNew)
            
            // Success — close sheet
            emailChangeLoading = false
            showEmailChangeSheet = false
            
            // The email will only update after the user verifies via the link
            // For now, show a temporary note (the Verified row already handles status)
            emailChangeError = nil
        } catch {
            emailChangeLoading = false
            let nsError = error as NSError
            switch nsError.code {
            case AuthErrorCode.wrongPassword.rawValue:
                emailChangeError = "Incorrect password. Please try again."
            case AuthErrorCode.invalidEmail.rawValue:
                emailChangeError = "The new email address is invalid."
            case AuthErrorCode.emailAlreadyInUse.rawValue:
                emailChangeError = "This email is already in use by another account."
            case AuthErrorCode.requiresRecentLogin.rawValue:
                emailChangeError = "For security, please sign out and sign back in, then try again."
            default:
                emailChangeError = error.localizedDescription
            }
        }
    }
    
    // MARK: - Profile Header
    private var profileHeader: some View {
        CSPageHeader(title: "Profile", leadingAction: { dismiss() })
    }
    
    // MARK: - Sign In Card (prominent, full-width)
    private var profileSignInCard: some View {
        Button {
            impactLight.impactOccurred()
            showAuthOptions = true
        } label: {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    // Branded icon
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [BrandColors.goldBase.opacity(0.2), BrandColors.goldBase.opacity(0.08)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 44, height: 44)
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(BrandColors.goldBase)
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Sign in to your account")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(DS.Adaptive.textPrimary)
                        
                        Text("Sync portfolio, alerts & conversations across devices")
                            .font(.caption)
                            .foregroundColor(DS.Adaptive.textSecondary)
                            .lineLimit(2)
                    }
                    
                    Spacer(minLength: 0)
                }
                
                // Gold CTA button
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Sign In or Create Account")
                        .font(.subheadline.weight(.bold))
                }
                .foregroundStyle(PremiumButtonTokens.contentGradient(isDark: colorScheme == .dark))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                colorScheme == .dark
                                    ? Color.white.opacity(0.055)
                                    : Color.black.opacity(0.04)
                            )
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(PremiumButtonTokens.radialGlassFill(isDark: colorScheme == .dark))
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(PremiumButtonTokens.topShine(isDark: colorScheme == .dark))
                            .padding(1)
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            PremiumButtonTokens.rimStroke(isDark: colorScheme == .dark),
                            lineWidth: colorScheme == .dark ? 1 : 1.2
                        )
                )
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [BrandColors.goldBase.opacity(0.3), DS.Adaptive.stroke],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.5
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Resolved Social Avatar
    
    /// Resolved avatar preset (if user has chosen one via social profile)
    private var resolvedPreset: PresetAvatar? {
        guard !avatarPresetId.isEmpty else { return nil }
        return AvatarCatalog.avatar(withId: avatarPresetId)
    }
    
    // MARK: - Profile Avatar Section
    private var profileAvatarSection: some View {
        VStack(spacing: 12) {
            ZStack {
                // Priority: custom photo > preset avatar > initials
                if let image = profileImage {
                    // Custom uploaded photo
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [BrandColors.goldLight.opacity(0.3), BrandColors.goldDark.opacity(0.3)]
                                    : [Color(red: 0.96, green: 0.92, blue: 0.80), Color(red: 0.92, green: 0.86, blue: 0.70)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .overlay(
                            Circle()
                                .stroke(
                                    AngularGradient(
                                        colors: [BrandColors.goldLight, BrandColors.goldBase, BrandColors.goldDark, BrandColors.goldBase, BrandColors.goldLight],
                                        center: .center
                                    ),
                                    lineWidth: 2.5
                                )
                        )
                    
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 94, height: 94)
                        .clipShape(Circle())
                    
                } else if let preset = resolvedPreset {
                    // Social avatar preset icon
                    ZStack {
                        // Gold ring
                        Circle()
                            .fill(
                                AngularGradient(
                                    colors: [BrandColors.goldLight, BrandColors.goldBase, BrandColors.goldDark, BrandColors.goldBase, BrandColors.goldLight],
                                    center: .center
                                )
                            )
                            .frame(width: 100, height: 100)
                        
                        // Preset gradient background
                        Circle()
                            .fill(preset.gradient)
                            .frame(width: 90, height: 90)
                        
                        // Preset icon or asset image
                        if let assetName = preset.assetImageName {
                            Image(assetName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 56, height: 56)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: preset.iconName)
                                .font(.system(size: 38, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    
                } else {
                    // Initials fallback
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [BrandColors.goldLight.opacity(0.3), BrandColors.goldDark.opacity(0.3)]
                                    : [Color(red: 0.96, green: 0.92, blue: 0.80), Color(red: 0.92, green: 0.86, blue: 0.70)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 100, height: 100)
                        .overlay(
                            Circle()
                                .stroke(
                                    AngularGradient(
                                        colors: [BrandColors.goldLight, BrandColors.goldBase, BrandColors.goldDark, BrandColors.goldBase, BrandColors.goldLight],
                                        center: .center
                                    ),
                                    lineWidth: 2.5
                                )
                        )
                    
                    Text(initials)
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .foregroundColor(colorScheme == .dark ? BrandColors.goldBase : Color(red: 0.55, green: 0.42, blue: 0.08))
                }
                
                // Edit badge — opens avatar picker
                Button(action: {
                    impactLight.impactOccurred()
                    showAvatarPicker = true
                }) {
                    ZStack {
                        Circle()
                            .fill(BrandColors.goldBase)
                            .frame(width: 32, height: 32)
                        Image(systemName: "camera.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.black)
                    }
                }
                .accessibilityLabel("Change avatar")
                .offset(x: 35, y: 35)
            }
            
            VStack(spacing: 4) {
                Text(effectiveDisplayName)
                    .font(.title2.weight(.bold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text(profileSubtitle)
                    .font(.subheadline)
                    .foregroundColor(BrandColors.goldBase)
            }
        }
        .padding(.vertical, 20)
    }
    
    private var initials: String {
        let name = effectiveDisplayName
        let components = name.split(separator: " ")
        let firstInitial = components.first?.first.map(String.init) ?? ""
        let lastInitial = components.count > 1 ? components.last?.first.map(String.init) ?? "" : ""
        let result = (firstInitial + lastInitial).uppercased()
        return result.isEmpty ? "CS" : result
    }
    
    /// Format member since date
    private func formatMemberDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
    
    // MARK: - Profile Image Persistence
    
    private var profileImageURL: URL? {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        return documentsDirectory.appendingPathComponent("profile_image.jpg")
    }
    
    private func saveProfileImage(_ image: UIImage) {
        guard let url = profileImageURL,
              let data = image.jpegData(compressionQuality: 0.8) else { return }
        
        do {
            try data.write(to: url)
            profileImagePath = url.path
            profileImage = image
            
            // Upload to Firebase Storage for cloud backup
            ProfileSyncService.shared.uploadProfileImage(image)
        } catch {
            #if DEBUG
            print("[ProfileView] Failed to save profile image: \(error)")
            #endif
        }
    }
    
    private func loadProfileImage() {
        guard let url = profileImageURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return
        }
        profileImage = image
    }
    
    private func deleteProfileImage() {
        guard let url = profileImageURL else { return }
        try? FileManager.default.removeItem(at: url)
        profileImagePath = ""
    }
}

// MARK: - Profile Section Container

struct ProfileSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(DS.Adaptive.textTertiary)
                .padding(.bottom, 6)
            
            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
                    )
            )
        }
    }
}

// MARK: - Profile Divider

struct ProfileDivider: View {
    var body: some View {
        Rectangle()
            .fill(DS.Adaptive.stroke)
            .frame(height: 0.5)
            .padding(.leading, 44)
    }
}

// MARK: - Profile Editable Row

struct ProfileEditableRow: View {
    let icon: String
    let title: String
    let value: String
    @Binding var isEditing: Bool
    @Binding var tempValue: String
    let onSave: () -> Void
    var keyboardType: UIKeyboardType = .default
    
    @State private var showEditSheet = false
    
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    
    var body: some View {
        Button(action: {
            impactLight.impactOccurred()
            tempValue = value == "Not set" ? "" : value
            showEditSheet = true
        }) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(BrandColors.goldBase.opacity(0.12))
                        .frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(BrandColors.goldBase)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    Text(value)
                        .font(.body)
                        .foregroundColor(DS.Adaptive.textPrimary)
                }
                
                Spacer()
                
                Image(systemName: "pencil")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit \(title)")
        .accessibilityValue(value)
        .sheet(isPresented: $showEditSheet) {
            ProfileFieldEditor(
                title: title,
                value: $tempValue,
                keyboardType: keyboardType,
                isPresented: $showEditSheet,
                onSave: onSave
            )
        }
    }
}

// MARK: - Profile Field Editor Sheet

struct ProfileFieldEditor: View {
    let title: String
    @Binding var value: String
    var keyboardType: UIKeyboardType = .default
    @Binding var isPresented: Bool
    let onSave: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var validationError: String? = nil
    @FocusState private var isFocused: Bool
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    
    /// Validates the input based on field type
    private func validateInput() -> Bool {
        validationError = nil
        
        switch keyboardType {
        case .emailAddress:
            if !value.isEmpty && !isValidEmail(value) {
                validationError = "Please enter a valid email address"
                return false
            }
        case .phonePad:
            if !value.isEmpty && !isValidPhone(value) {
                validationError = "Please enter a valid phone number"
                return false
            }
        default:
            break
        }
        return true
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    private func isValidPhone(_ phone: String) -> Bool {
        // Allow common phone formats: digits, spaces, dashes, parentheses, plus sign
        let phoneRegex = "^[+]?[(]?[0-9]{1,4}[)]?[-\\s./0-9]*$"
        let phonePredicate = NSPredicate(format: "SELF MATCHES %@", phoneRegex)
        return phone.count >= 7 && phonePredicate.evaluate(with: phone)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Input field with proper styling
                VStack(alignment: .leading, spacing: 8) {
                    Text(title)
                        .font(.caption.weight(.medium))
                        .foregroundColor(DS.Adaptive.textTertiary)
                    
                    TextField("Enter \(title.lowercased())", text: $value)
                        .font(.body)
                        .foregroundColor(DS.Adaptive.textPrimary)
                        .keyboardType(keyboardType)
                        .textContentType(keyboardType == .emailAddress ? .emailAddress : keyboardType == .phonePad ? .telephoneNumber : .name)
                        .autocorrectionDisabled(keyboardType == .emailAddress || keyboardType == .phonePad)
                        .textInputAutocapitalization(keyboardType == .emailAddress ? .never : .words)
                        .focused($isFocused)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(DS.Adaptive.cardBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(validationError != nil ? Color.red : (isFocused ? BrandColors.goldBase : DS.Adaptive.stroke), lineWidth: isFocused ? 1.5 : 0.5)
                                )
                        )
                        .onChange(of: value) { _, _ in
                            validationError = nil // Clear error as user types
                        }
                    
                    // Validation error message
                    if let error = validationError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.leading, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 20)
                
                Spacer()
            }
            .background(DS.Adaptive.background.ignoresSafeArea())
            .navigationTitle("Edit \(title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        impactLight.impactOccurred()
                        isPresented = false
                    }
                    .foregroundColor(DS.Adaptive.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        impactLight.impactOccurred()
                        if validateInput() {
                            onSave()
                            isPresented = false
                        }
                    }
                    .font(.headline)
                    .foregroundColor(DS.Adaptive.gold)
                }
            }
            .toolbarBackground(DS.Adaptive.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
            .onAppear {
                // Auto-focus the text field when sheet appears
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isFocused = true
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Profile Info Row (Non-editable)

struct ProfileInfoRow: View {
    let icon: String
    let title: String
    let value: String
    var valueColor: Color = DS.Adaptive.textSecondary
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(BrandColors.goldBase.opacity(0.12))
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(BrandColors.goldBase)
            }
            
            Text(title)
                .font(.body)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .foregroundColor(valueColor)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

// MARK: - Bio Editor Sheet

struct ProfileBioEditor: View {
    @Binding var bio: String
    @Binding var tempValue: String
    @Binding var isPresented: Bool
    
    @Environment(\.colorScheme) private var colorScheme
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let maxCharacters = 250
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                TextEditor(text: $tempValue)
                    .font(.body)
                    .padding()
                    .scrollContentBackground(.hidden)
                    .background(DS.Adaptive.cardBackground)
                    .onChange(of: tempValue) { _, newValue in
                        // Limit to max characters
                        if newValue.count > maxCharacters {
                            tempValue = String(newValue.prefix(maxCharacters))
                        }
                    }
                
                HStack {
                    Text("\(tempValue.count)/\(maxCharacters) characters")
                        .font(.caption)
                        .foregroundColor(tempValue.count >= maxCharacters ? .orange : DS.Adaptive.textTertiary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .background(DS.Adaptive.background.ignoresSafeArea())
            .navigationTitle("Edit Bio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        impactLight.impactOccurred()
                        isPresented = false
                    }
                    .foregroundColor(DS.Adaptive.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        impactLight.impactOccurred()
                        bio = String(tempValue.prefix(maxCharacters))
                        ProfileSyncService.shared.syncProfileToFirestore()
                        isPresented = false
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Adaptive.gold)
                }
            }
            .toolbarBackground(DS.Adaptive.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme == .dark ? .dark : .light, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Profile Image Picker

struct ProfileImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    var onImageSelected: ((UIImage) -> Void)?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        picker.allowsEditing = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ProfileImagePicker
        
        init(_ parent: ProfileImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let editedImage = info[.editedImage] as? UIImage {
                parent.image = editedImage
                parent.onImageSelected?(editedImage)
            } else if let originalImage = info[.originalImage] as? UIImage {
                parent.image = originalImage
                parent.onImageSelected?(originalImage)
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
