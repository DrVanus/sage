//
//  SecuritySettingsView.swift
//  CryptoSage
//
//  Security and authentication settings including biometric auth,
//  PIN code, API key management, and data protection.
//

import SwiftUI
import AuthenticationServices

// MARK: - Security & Login View

struct SecuritySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var biometricAuth = BiometricAuthManager.shared
    @StateObject private var securityManager = SecurityManager.shared
    @StateObject private var pinManager = PINAuthManager.shared
    @AppStorage("isPasscodeEnabled") private var isPasscodeEnabled = false
    @AppStorage("enable2FA") private var enable2FA = false
    @State private var isTogglingBiometric = false
    @State private var showBiometricError = false
    @State private var biometricErrorMessage = ""
    @State private var showPINSetup = false
    @State private var showPINChange = false
    @State private var showPINActionMenu = false
    @State private var showAPIKeySettings = false
    @State private var showRemovePINAlert = false
    @State private var showWipeDataAlert = false
    @State private var showWipeSuccess = false
    @State private var isAuthenticatingForWipe = false
    
    private let autoLockOptions: [(String, TimeInterval)] = [
        ("Immediately", 0),
        ("After 1 minute", 60),
        ("After 5 minutes", 300),
        ("After 15 minutes", 900),
        ("After 30 minutes", 1800)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            CSPageHeader(title: "Security & Login", leadingAction: { dismiss() })
            
            Form {
            Section(header: Text("App Protection")) {
                // Biometric toggle with proper authentication
                HStack {
                    Image(systemName: biometricAuth.biometricType.iconName)
                        .foregroundColor(BrandColors.goldBase)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lock with \(biometricAuth.biometricType.displayName)")
                        if !biometricAuth.canUseBiometric && biometricAuth.biometricType == .none {
                            Text("Not available on this device")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    if isTogglingBiometric {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Toggle("", isOn: Binding(
                            get: { biometricAuth.isBiometricEnabled },
                            set: { _ in toggleBiometric() }
                        ))
                        .labelsHidden()
                        .disabled(!biometricAuth.canUseDeviceAuth)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Lock with \(biometricAuth.biometricType.displayName)")
                .accessibilityValue(biometricAuth.isBiometricEnabled ? "Enabled" : "Disabled")
                
                // PIN code backup (like Coinbase/Binance)
                HStack {
                    Image(systemName: "rectangle.grid.3x3")
                        .foregroundColor(BrandColors.goldBase)
                        .frame(width: 24)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PIN Code")
                        Text(pinManager.isPINSet ? "Enabled as backup" : "Set up a 6-digit PIN")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if pinManager.isPINSet {
                        Button {
                            #if os(iOS)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            #endif
                            showPINActionMenu = true
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundColor(BrandColors.goldBase)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("PIN options")
                        .popover(isPresented: $showPINActionMenu, arrowEdge: .leading) {
                            PINActionMenu(
                                isPresented: $showPINActionMenu,
                                onChangePIN: { showPINChange = true },
                                onRemovePIN: { showRemovePINAlert = true }
                            )
                            .presentationCompactAdaptation(.popover)
                        }
                    } else {
                        Button("Set Up") {
                            showPINSetup = true
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(BrandColors.goldBase)
                    }
                }
                
                // Auto-lock timeout picker (only show if any lock is enabled)
                if biometricAuth.isBiometricEnabled || pinManager.isPINSet {
                    Picker("Auto-Lock", selection: $securityManager.autoLockTimeout) {
                        ForEach(autoLockOptions, id: \.1) { option in
                            Text(option.0).tag(option.1)
                        }
                    }
                }
            }
            
            // API Keys Section - Developer Mode Only
            // Regular users don't need to manage API keys - the app uses built-in services
            if SubscriptionManager.shared.isDeveloperMode {
                Section(header: Text("API Keys (Developer)")) {
                    Button(action: { showAPIKeySettings = true }) {
                        HStack {
                            Image(systemName: "key.fill")
                                .foregroundColor(BrandColors.goldBase)
                                .frame(width: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Manage API Keys")
                                Text("OpenAI, Binance, 3Commas, and more")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)
                }
                
                // 2FA for Trading - Developer Mode Only (trading is disabled for regular users)
                Section(header: Text("Trading Security (Developer)")) {
                    Toggle("Enable 2FA for Trading", isOn: $enable2FA)
                    
                    Text("Two-factor authentication for live trading operations.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Section(header: Text("Security Warnings")) {
                Toggle("Show Security Alerts", isOn: $securityManager.showSecurityWarnings)
                
                if securityManager.isDeviceCompromised {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Device security may be compromised")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }
            
            Section(header: Text("Security Status")) {
                VStack(alignment: .leading, spacing: 8) {
                    // API Keys status - only show in dev mode
                    if SubscriptionManager.shared.isDeveloperMode {
                        SecurityStatusRow(
                            icon: "lock.shield.fill",
                            title: "API Keys",
                            status: "Encrypted in Keychain",
                            isSecure: true
                        )
                    }
                    SecurityStatusRow(
                        icon: "network.badge.shield.half.filled",
                        title: "Network",
                        status: "TLS 1.2+ Enforced",
                        isSecure: true
                    )
                    SecurityStatusRow(
                        icon: "iphone.badge.checkmark",
                        title: "Device",
                        status: securityManager.isDeviceCompromised ? "Potentially Compromised" : "Secure",
                        isSecure: !securityManager.isDeviceCompromised
                    )
                    SecurityStatusRow(
                        icon: biometricAuth.biometricType.iconName,
                        title: "App Lock",
                        status: biometricAuth.isBiometricEnabled || pinManager.isPINSet ? "Enabled" : "Not Set",
                        isSecure: biometricAuth.isBiometricEnabled || pinManager.isPINSet,
                        isOptional: true   // App Lock is recommended, not a vulnerability
                    )
                    SecurityStatusRow(
                        icon: "externaldrive.fill.badge.checkmark",
                        title: "Portfolio Data",
                        status: "AES-256 Encrypted",
                        isSecure: true
                    )
                    // Cloud sync status — not a security risk when disabled, just informational
                    SecurityStatusRow(
                        icon: "icloud.fill",
                        title: "Cloud Sync",
                        status: AuthenticationManager.shared.isAuthenticated
                            ? "Profile, Watchlist, Paper Trading, Chats"
                            : "Not Signed In",
                        isSecure: AuthenticationManager.shared.isAuthenticated,
                        isOptional: true   // Cloud sync is a convenience feature, not security
                    )
                }
                .padding(.vertical, 4)
            }
            
            Section(header: Text("Data Management")) {
                Button(action: {
                    authenticateForWipe()
                }) {
                    HStack {
                        Image(systemName: "trash.fill")
                            .foregroundColor(.red)
                        Text("Wipe All User Data")
                            .foregroundColor(.red)
                        Spacer()
                        if isAuthenticatingForWipe {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }
                }
                .disabled(isAuthenticatingForWipe)
                
                Text("This will permanently delete all portfolio data, transactions, connected accounts, and API keys from this device.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if showWipeSuccess {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("All data has been wiped.")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.green)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .tint(BrandColors.goldBase)
        } // end outer VStack
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .enableInteractivePopGesture()
        .edgeSwipeToDismiss(onDismiss: { dismiss() })
        .alert("Authentication Error", isPresented: $showBiometricError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(biometricErrorMessage)
        }
        .alert("Wipe All Data?", isPresented: $showWipeDataAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Wipe Everything", role: .destructive) {
                SecureUserDataManager.shared.wipeAllDataIncludingSecrets()
                // Provide feedback
                let notification = UINotificationFeedbackGenerator()
                notification.notificationOccurred(.success)
                withAnimation(.easeInOut(duration: 0.3)) {
                    showWipeSuccess = true
                }
                // Hide success banner after a few seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    withAnimation { showWipeSuccess = false }
                }
            }
        } message: {
            Text("This will permanently delete all your data including API keys. This action cannot be undone.")
        }
        .alert("Remove PIN?", isPresented: $showRemovePINAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Remove", role: .destructive) {
                pinManager.removePIN()
                let notification = UINotificationFeedbackGenerator()
                notification.notificationOccurred(.success)
            }
        } message: {
            Text("This will remove your PIN code. You'll need to set it up again if you want to use PIN authentication.")
        }
        .sheet(isPresented: $showPINSetup) {
            NavigationStack {
                PINEntryView(mode: .setup) { success in
                    showPINSetup = false
                    if success {
                        biometricAuth.enablePINFallback()
                    }
                }
                .navigationTitle("Set Up PIN")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showPINChange) {
            NavigationStack {
                PINEntryView(mode: .change) { success in
                    showPINChange = false
                }
                .navigationTitle("Change PIN")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .sheet(isPresented: $showAPIKeySettings) {
            APIKeySettingsView()
        }
    }
    
    /// Gate the wipe action behind device authentication when available.
    /// If biometric or PIN is set up, the user must authenticate first.
    /// If no auth is configured, fall through to the confirmation alert directly.
    private func authenticateForWipe() {
        let hasAuth = biometricAuth.isBiometricEnabled || pinManager.isPINSet
        
        if hasAuth {
            isAuthenticatingForWipe = true
            Task {
                let success = await biometricAuth.authenticate(reason: "Authenticate to wipe all data")
                await MainActor.run {
                    isAuthenticatingForWipe = false
                    if success {
                        showWipeDataAlert = true
                    }
                    // If auth fails, do nothing — user simply can't proceed
                }
            }
        } else {
            // No authentication configured — show alert directly
            showWipeDataAlert = true
        }
    }
    
    private func toggleBiometric() {
        isTogglingBiometric = true
        Task {
            let success = await biometricAuth.toggleBiometric()
            await MainActor.run {
                isTogglingBiometric = false
                if !success, let error = biometricAuth.authError {
                    biometricErrorMessage = error
                    showBiometricError = true
                }
            }
        }
    }
}

// MARK: - Security Status Row

struct SecurityStatusRow: View {
    let icon: String
    let title: String
    let status: String
    let isSecure: Bool
    /// When true, a non-secure status is shown as informational (gray)
    /// rather than a warning (orange). Use for optional features like Cloud Sync and App Lock
    /// that aren't security vulnerabilities when disabled.
    var isOptional: Bool = false
    
    private var statusColor: Color {
        if isSecure { return .green }
        return isOptional ? .secondary : .orange
    }
    
    private var badgeIcon: String {
        if isSecure { return "checkmark.circle.fill" }
        return isOptional ? "minus.circle.fill" : "exclamationmark.circle.fill"
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(statusColor)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.primary)
                Text(status)
                    .font(.caption2)
                    .foregroundColor(isSecure ? .secondary : (isOptional ? .secondary : .orange))
            }
            
            Spacer()
            
            Image(systemName: badgeIcon)
                .font(.caption)
                .foregroundColor(statusColor)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(status)")
        .accessibilityValue(isSecure ? "Secure" : (isOptional ? "Not configured" : "Needs attention"))
    }
}

// MARK: - Account Sign-In Section
/// Compact Apple Sign-In section for authentication and cloud sync
/// Used in both main Settings page and Security settings

struct AccountSignInSection: View {
    @ObservedObject private var authManager = AuthenticationManager.shared
    @State private var showAuthOptions = false
    
    var body: some View {
        if authManager.isAuthenticated {
            // Signed in state - compact cloud sync status
            signedInView
        } else {
            // Signed out state - compact single-line prompt
            signedOutView
        }
    }
    
    private var signedInView: some View {
        // Compact cloud sync status when signed in
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.icloud.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.green)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text("Cloud Sync Active")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Text("Your data syncs across all devices")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.green)
            }
            
            // Show what data types are synced
            HStack(spacing: 6) {
                cloudSyncChip("Profile")
                cloudSyncChip("Watchlist")
                cloudSyncChip("Paper Trading")
                cloudSyncChip("Chat History")
                Spacer()
            }
            .padding(.leading, 26)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cloud Sync Active. Syncing profile, watchlist, paper trading, and chat history across all devices.")
    }
    
    private func cloudSyncChip(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(DS.Adaptive.textSecondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.green.opacity(0.1))
            )
            .overlay(
                Capsule()
                    .stroke(Color.green.opacity(0.2), lineWidth: 0.5)
            )
    }
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var signedOutView: some View {
        return VStack(spacing: 12) {
            // Info row
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(BrandColors.goldBase.opacity(0.12))
                        .frame(width: 30, height: 30)
                    Image(systemName: "icloud.and.arrow.up")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(colorScheme == .dark ? BrandColors.goldBase : BrandColors.goldDark)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sign in to sync")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(DS.Adaptive.textPrimary)
                    
                    Text("Backup & sync across devices")
                        .font(.caption)
                        .foregroundColor(DS.Adaptive.textSecondary)
                }
                
                Spacer()
            }
            .padding(.vertical, 2)
            
            // Full-width CTA sign-in button - gold in dark mode, charcoal in light mode
            Button {
                showAuthOptions = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Sign In")
                        .font(.subheadline.weight(.bold))
                }
            }
            .buttonStyle(
                PremiumPrimaryCTAStyle(
                    height: 40,
                    horizontalPadding: 14,
                    cornerRadius: 10,
                    font: .subheadline.weight(.bold)
                )
            )
        }
        .sheet(isPresented: $showAuthOptions) {
            AuthOptionsView()
        }
        .accessibilityLabel("Sign in to sync your data across devices")
    }
}

// MARK: - PIN Action Menu (Styled popover)

struct PINActionMenu: View {
    @Binding var isPresented: Bool
    let onChangePIN: () -> Void
    let onRemovePIN: () -> Void
    
    var body: some View {
        VStack(spacing: 2) {
            actionRow(title: "Change PIN", icon: "pencil", action: onChangePIN)
            
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
            
            actionRow(title: "Remove PIN", icon: "trash", isDestructive: true, action: onRemovePIN)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .background(DS.Adaptive.cardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            LinearGradient(colors: [Color.white.opacity(0.10), .clear], startPoint: .top, endPoint: .center)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .allowsHitTesting(false)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 0.75)
                .allowsHitTesting(false)
        )
        .frame(minWidth: 140, maxWidth: 180)
    }
    
    @ViewBuilder
    private func actionRow(title: String, icon: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button {
            #if os(iOS)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            action()
            isPresented = false
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isDestructive ? Color.red : Color.white.opacity(0.9))
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isDestructive ? Color.red : Color.white.opacity(0.92))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
