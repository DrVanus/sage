//
//  SettingsComponents.swift
//  CryptoSage
//
//  Reusable UI components for Settings screens including rows,
//  sections, toggles, and other shared elements.
//

import SwiftUI

// MARK: - Settings Section Container

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(DS.Adaptive.textTertiary)
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            
            VStack(spacing: 0) {
                content
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DS.Adaptive.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(DS.Adaptive.stroke, lineWidth: 0.5)
                    )
            )
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Settings Divider

struct SettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(DS.Adaptive.stroke)
            .frame(height: 0.5)
            .padding(.leading, 44)
    }
}

// MARK: - Settings Row

struct SettingsRow: View {
    let icon: String
    let title: String
    var showChevron: Bool = true
    var iconColor: Color = BrandColors.goldBase
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 30, height: 30)
                
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(iconColor)
            }
            
            Text(title)
                .font(.body)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Spacer()
            
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.Adaptive.textTertiary)
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Settings Row with Value

struct SettingsRowWithValue: View {
    let icon: String
    let title: String
    let value: String
    var iconColor: Color = BrandColors.goldBase
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(iconColor.opacity(0.12))
                    .frame(width: 30, height: 30)
                
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(iconColor)
            }
            
            Text(title)
                .font(.body)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .foregroundColor(DS.Adaptive.textSecondary)
            
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Settings Toggle Row

struct SettingsToggleRow: View {
    let icon: String
    let title: String
    @Binding var isOn: Bool
    var iconColor: Color? = nil  // Optional custom icon color
    
    private var effectiveIconColor: Color {
        iconColor ?? BrandColors.goldBase
    }
    
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(effectiveIconColor.opacity(0.12))
                    .frame(width: 30, height: 30)
                
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(effectiveIconColor)
            }
            
            Text(title)
                .font(.body)
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(effectiveIconColor)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Profile Card Button Style

struct ProfileCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Profile Header View

struct ProfileHeaderView: View {
    // Auth state - observe for real-time updates
    @ObservedObject private var authManager = AuthenticationManager.shared
    
    // Observe ProfileSyncService so the header re-renders when cloud data is restored
    @ObservedObject private var profileSync = ProfileSyncService.shared
    
    // Profile data from UserDefaults (synced by AuthenticationManager on sign-in)
    @AppStorage("profile.displayName") private var displayName: String = ""
    @AppStorage("profile.email") private var email: String = ""
    
    // Subscription state for dynamic plan display
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    
    /// Display name - uses auth user data, falls back to profile storage, then default
    private var effectiveDisplayName: String {
        if let authName = authManager.currentUser?.displayName, !authName.isEmpty {
            return authName
        }
        if !displayName.isEmpty {
            return displayName
        }
        return "CryptoSage User"
    }
    
    /// Email - uses auth user data, falls back to profile storage
    private var effectiveEmail: String {
        if let authEmail = authManager.currentUser?.email, !authEmail.isEmpty {
            return authEmail
        }
        if !email.isEmpty {
            return email
        }
        return authManager.isAuthenticated ? "Signed in with Apple" : "Tap to sign in"
    }
    
    /// Computed initials from display name (e.g., "John Doe" -> "JD")
    private var initials: String {
        let name = effectiveDisplayName
        let components = name.split(separator: " ")
        let firstInitial = components.first?.first.map(String.init) ?? ""
        let lastInitial = components.count > 1 ? components.last?.first.map(String.init) ?? "" : ""
        let result = (firstInitial + lastInitial).uppercased()
        return result.isEmpty ? "CS" : result
    }
    
    /// Dynamic plan display name that respects developer mode
    private var planDisplayName: String {
        let tier = subscriptionManager.effectiveTier
        if subscriptionManager.isDeveloperMode {
            return "\(tier.displayName) (Dev)"
        }
        return "\(tier.displayName) Plan"
    }
    
    /// Icon for the current tier
    private var tierIcon: String {
        switch subscriptionManager.effectiveTier {
        case .free: return "checkmark.seal.fill"
        case .pro: return "bolt.seal.fill"
        case .premium: return "crown.fill"
        }
    }
    
    /// Color for the tier badge
    private var tierColor: Color {
        switch subscriptionManager.effectiveTier {
        case .free: return BrandColors.goldBase
        case .pro: return BrandColors.goldBase
        case .premium: return .purple
        }
    }
    
    var body: some View {
        HStack(spacing: 14) {
            // Unified avatar — uses ProfileAvatarMini for consistency across the app
            ProfileAvatarMini(size: 56)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(effectiveDisplayName)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(DS.Adaptive.textPrimary)
                
                Text(effectiveEmail)
                    .font(.subheadline)
                    .foregroundColor(DS.Adaptive.textSecondary)
                
                HStack(spacing: 4) {
                    Image(systemName: tierIcon)
                        .font(.caption2)
                    Text(planDisplayName)
                        .font(.caption.weight(.medium))
                }
                .foregroundColor(tierColor)
                .padding(.top, 1)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DS.Adaptive.textTertiary)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DS.Adaptive.cardBackgroundElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    BrandColors.goldBase.opacity(0.5),
                                    BrandColors.goldBase.opacity(0.15),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Profile: \(effectiveDisplayName), \(planDisplayName)")
        .accessibilityHint("Tap to edit profile")
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// NOTE: LockedFeatureBadge is defined in SubscriptionManager.swift

// MARK: - Consistent Navigation Button

/// Reusable navigation button matching the app's premium gold style.
/// Use `icon: "chevron.left"` for back buttons (pushed views) and
/// `icon: "xmark"` for dismiss buttons (sheet/modal views).
/// Unified premium navigation button used across the entire app.
/// Gold gradient icon inside a subtle glass-morphic circle with gold-tinted rim.
/// Use for back buttons, close buttons, and any navigation-level icon buttons.
struct CSNavButton: View {
    let icon: String
    let action: () -> Void
    var accessibilityText: String = "Back"
    var accessibilityHintText: String = "Return to previous screen"
    /// Optional: set to true for toolbar placements where the button needs
    /// to be slightly smaller (32pt) to fit the native toolbar height.
    var compact: Bool = false
    
    @Environment(\.colorScheme) private var colorScheme
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    
    private var isDark: Bool { colorScheme == .dark }
    private var size: CGFloat { compact ? 32 : 36 }
    private var iconSize: CGFloat { compact ? 14 : 15 }
    
    var body: some View {
        Button(action: {
            impactLight.impactOccurred()
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundStyle(
                    isDark ? AnyShapeStyle(chipGoldGradient) : AnyShapeStyle(BrandColors.goldBase)
                )
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.04))
                )
                .overlay(
                    Circle()
                        .stroke(
                            isDark
                                ? BrandColors.goldBase.opacity(0.18)
                                : BrandColors.goldBase.opacity(0.12),
                            lineWidth: 0.8
                        )
                )
                .contentShape(Circle())
        }
        .buttonStyle(CSNavButtonPressStyle())
        .accessibilityLabel(accessibilityText)
        .accessibilityHint(accessibilityHintText)
    }
}

/// Premium press animation for CSNavButton: scale + opacity + slight brightness shift.
private struct CSNavButtonPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// Reusable page header bar matching the Settings page style.
/// Centers the title between a leading nav button and optional trailing content.
struct CSPageHeader<Trailing: View>: View {
    let title: String
    let leadingIcon: String
    let leadingAction: () -> Void
    let trailing: Trailing
    
    var body: some View {
        HStack {
            CSNavButton(
                icon: leadingIcon,
                action: leadingAction,
                accessibilityText: leadingIcon == "xmark" ? "Close" : "Back",
                accessibilityHintText: "Return to previous screen"
            )
            
            Spacer()
            
            Text(title)
                .font(.headline.weight(.semibold))
                .foregroundColor(DS.Adaptive.textPrimary)
            
            Spacer()
            
            trailing
                .frame(width: 36, height: 36)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(DS.Adaptive.background)
    }
}

// Convenience initializer without trailing content
extension CSPageHeader where Trailing == Color {
    init(title: String, leadingIcon: String = "chevron.left", leadingAction: @escaping () -> Void) {
        self.title = title
        self.leadingIcon = leadingIcon
        self.leadingAction = leadingAction
        self.trailing = Color.clear
    }
}

// Initializer with custom trailing content
extension CSPageHeader {
    init(title: String, leadingIcon: String = "chevron.left", leadingAction: @escaping () -> Void, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.leadingIcon = leadingIcon
        self.leadingAction = leadingAction
        self.trailing = trailing()
    }
}
