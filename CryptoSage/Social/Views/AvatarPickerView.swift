//
//  AvatarPickerView.swift
//  CryptoSage
//
//  Avatar selection interface with categorized preset icons
//  and initials option. Users can browse and select their avatar.
//

import SwiftUI

// MARK: - Avatar Picker View

/// Full-screen avatar picker with categories and preview
public struct AvatarPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    
    let username: String
    @Binding var selectedAvatarId: String?
    var onSave: ((String?) -> Void)?
    
    @State private var selectedCategory: AvatarCategory = .crypto
    @State private var tempSelectedId: String?
    @State private var showInitials: Bool = false
    @State private var showPaywall: Bool = false
    
    private var isDark: Bool { colorScheme == .dark }
    
    /// Check if user has premium subscription (Pro or Premium tier)
    private var isPremiumUser: Bool {
        subscriptionManager.effectiveTier == .pro || subscriptionManager.effectiveTier == .premium
    }
    
    /// Check if developer mode is active
    private var isDeveloperMode: Bool {
        subscriptionManager.isDeveloperMode
    }
    
    /// Categories to show (developer tab only visible in developer mode)
    private var visibleCategories: [AvatarCategory] {
        if isDeveloperMode {
            return AvatarCategory.allCases
        } else {
            return AvatarCategory.allCases.filter { $0 != .developer }
        }
    }
    
    public init(
        username: String,
        selectedAvatarId: Binding<String?>,
        onSave: ((String?) -> Void)? = nil
    ) {
        self.username = username
        self._selectedAvatarId = selectedAvatarId
        self.onSave = onSave
        self._tempSelectedId = State(initialValue: selectedAvatarId.wrappedValue)
        self._showInitials = State(initialValue: selectedAvatarId.wrappedValue == nil)
    }
    
    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Preview section
                previewSection
                    .padding(.vertical, 24)
                
                Divider()
                    .background(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1))
                
                // Category tabs
                categoryTabs
                    .padding(.vertical, 12)
                
                // Avatar grid
                avatarGrid
            }
            .background(isDark ? Color.black : Color(UIColor.systemBackground))
            .navigationTitle("Choose Avatar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.secondary)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveSelection()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(DS.Adaptive.gold)
                }
            }
            .toolbarBackground(DS.Adaptive.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(isDark ? .dark : .light, for: .navigationBar)
        }
        .sheet(isPresented: $showPaywall) {
            SubscriptionPricingView()
        }
    }
    
    // MARK: - Preview Section
    
    private var previewSection: some View {
        VStack(spacing: 16) {
            // Large avatar preview
            ZStack {
                // Animated background glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [previewGradientColor.opacity(0.3), .clear],
                            center: .center,
                            startRadius: 40,
                            endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)
                
                UserAvatarView(
                    username: username,
                    avatarPresetId: showInitials ? nil : tempSelectedId,
                    size: 100,
                    showRing: true,
                    ringColor: .yellow
                )
            }
            
            // Username display
            Text("@\(username)")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
            
            // Selection info
            if showInitials {
                Text("Using your initials")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            } else if let id = tempSelectedId,
                      let preset = AvatarCatalog.avatar(withId: id) {
                Text(preset.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(preset.primaryColor)
            }
        }
    }
    
    private var previewGradientColor: Color {
        if showInitials {
            return AvatarGradientGenerator.primaryColor(for: username)
        } else if let id = tempSelectedId,
                  let preset = AvatarCatalog.avatar(withId: id) {
            return preset.primaryColor
        }
        return .blue
    }
    
    // MARK: - Category Tabs
    
    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Initials option (special tab)
                initialsTab
                
                // Category tabs (developer tab only in dev mode)
                ForEach(visibleCategories) { category in
                    categoryTab(for: category)
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    private var initialsTab: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showInitials = true
                tempSelectedId = nil
            }
        } label: {
            HStack(spacing: 6) {
                Text(AvatarDisplayHelper.initials(from: username))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(showInitials ? .black : .secondary)
                
                Text("Initials")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(showInitials ? .black : .secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(showInitials ? Color.yellow : (isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func categoryTab(for category: AvatarCategory) -> some View {
        let isSelected = !showInitials && selectedCategory == category
        
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showInitials = false
                selectedCategory = category
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: category.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isSelected ? .black : .secondary)
                
                Text(category.rawValue)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? .black : .secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color.yellow : (isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Avatar Grid
    
    private var avatarGrid: some View {
        ScrollView {
            if showInitials {
                // Show initials customization info
                initialsInfoView
            } else {
                VStack(spacing: 16) {
                    // Premium header for Special category
                    if selectedCategory == .special {
                        premiumCategoryHeader
                    }
                    
                    // Developer header for Developer category
                    if selectedCategory == .developer {
                        developerCategoryHeader
                    }
                    
                    // Show avatars for selected category
                    let avatars = AvatarCatalog.avatars(for: selectedCategory)
                    let columns = [GridItem(.adaptive(minimum: 70, maximum: 90), spacing: 12)]
                    
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(avatars) { avatar in
                            avatarGridItem(avatar)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.vertical, 12)
            }
        }
    }
    
    // MARK: - Premium Category Header
    
    private var premiumCategoryHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.yellow, Color.orange],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("Premium Avatars")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                if isPremiumUser {
                    Text("Unlocked")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.green.opacity(0.15))
                        )
                } else {
                    Text("Pro/Premium")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.orange.opacity(0.15))
                        )
                }
            }
            .padding(.horizontal, 16)
            
            if !isPremiumUser {
                Button {
                    showPaywall = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14))
                        Text("Upgrade to unlock exclusive avatars")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [Color.purple, Color.blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(10)
                }
                .padding(.horizontal, 16)
            }
        }
    }
    
    // MARK: - Developer Category Header
    
    /// Adaptive developer green — softer in light mode, neon in dark mode
    private var devGreen: Color {
        isDark ? Color(hex: "#00FF41") : Color(hex: "#1B8C3A")
    }
    
    private var developerCategoryHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [devGreen, devGreen.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                Text("Developer Exclusive")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Text("Dev Mode")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(devGreen)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(devGreen.opacity(0.15))
                    )
            }
            .padding(.horizontal, 16)
            
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(devGreen)
                Text("These avatars are only available to developers. A rare flex.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
        }
    }
    
    private func avatarGridItem(_ avatar: PresetAvatar) -> some View {
        let isSelected = !showInitials && tempSelectedId == avatar.id
        let isLocked = (avatar.isPremium && !isPremiumUser) || (avatar.isDeveloperOnly && !isDeveloperMode)
        
        return Button {
            if isLocked {
                // Show paywall for locked premium avatars (developer icons just don't appear for non-devs)
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if avatar.isPremium && !isPremiumUser {
                    showPaywall = true
                }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    tempSelectedId = avatar.id
                    showInitials = false
                }
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    // Avatar
                    ZStack {
                        avatar.gradient
                        
                        if let assetName = avatar.assetImageName {
                            Image(assetName)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 34, height: 34)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: avatar.iconName)
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(
                                isDark
                                    ? Color.white.opacity(0.06)
                                    : Color.black.opacity(0.12),
                                lineWidth: isDark ? 0.5 : 1.0
                            )
                    )
                    .opacity(isLocked ? 0.5 : 1.0)
                    
                    // Locked overlay for premium avatars
                    if isLocked {
                        Circle()
                            .fill(Color.black.opacity(0.5))
                            .frame(width: 56, height: 56)
                        
                        Image(systemName: "lock.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    
                    // Selection indicator
                    if isSelected && !isLocked {
                        Circle()
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.yellow, .orange],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 3
                            )
                            .frame(width: 62, height: 62)
                        
                        // Checkmark
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.yellow)
                            .background(
                                Circle()
                                    .fill(isDark ? Color.black : Color.white)
                                    .padding(-2)
                            )
                            .offset(x: 20, y: 20)
                    }
                    
                    // Premium badge (crown for unlocked, lock badge for locked)
                    if avatar.isPremium {
                        ZStack {
                            Circle()
                                .fill(isDark ? Color.black : Color.white)
                                .frame(width: 20, height: 20)
                            
                            Image(systemName: isLocked ? "lock.fill" : "crown.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(isLocked ? .gray : .yellow)
                        }
                        .offset(x: 20, y: -20)
                    }
                    
                    // Developer badge
                    if avatar.isDeveloperOnly {
                        ZStack {
                            Circle()
                                .fill(isDark ? Color.black : Color.white)
                                .frame(width: 20, height: 20)
                            
                            Image(systemName: "hammer.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(Color(hex: "#00FF41"))
                        }
                        .offset(x: 20, y: -20)
                    }
                }
                
                // Name
                Text(avatar.name)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isLocked ? .secondary.opacity(0.6) : (isSelected ? .primary : .secondary))
                    .lineLimit(1)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var initialsInfoView: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 40)
            
            // Large initials preview
            UserAvatarView(
                username: username,
                avatarPresetId: nil,
                size: 80
            )
            
            Text("Your Initials")
                .font(.system(size: 18, weight: .semibold))
            
            Text("Your avatar will display your initials with a unique gradient color based on your username.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            // Color preview
            VStack(spacing: 8) {
                Text("Your unique color")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 4) {
                    ForEach(AvatarGradientGenerator.gradientColors(for: username), id: \.self) { color in
                        Circle()
                            .fill(color)
                            .frame(width: 24, height: 24)
                    }
                }
            }
            .padding(.top, 8)
            
            Spacer()
        }
    }
    
    // MARK: - Actions
    
    private func saveSelection() {
        if showInitials {
            selectedAvatarId = nil
        } else {
            selectedAvatarId = tempSelectedId
        }
        onSave?(selectedAvatarId)
        dismiss()
    }
}

// MARK: - Compact Avatar Picker

/// Inline avatar picker for forms and settings
public struct CompactAvatarPicker: View {
    let username: String
    @Binding var selectedAvatarId: String?
    
    @State private var showFullPicker: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    public init(username: String, selectedAvatarId: Binding<String?>) {
        self.username = username
        self._selectedAvatarId = selectedAvatarId
    }
    
    public var body: some View {
        Button {
            showFullPicker = true
        } label: {
            HStack(spacing: 12) {
                // Current avatar
                UserAvatarView(
                    username: username,
                    avatarPresetId: selectedAvatarId,
                    size: 50
                )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Avatar")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                    
                    if let id = selectedAvatarId,
                       let preset = AvatarCatalog.avatar(withId: id) {
                        Text(preset.name)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    } else {
                        Text("Using initials")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showFullPicker) {
            AvatarPickerView(username: username, selectedAvatarId: $selectedAvatarId)
        }
    }
}

// MARK: - Avatar Quick Select

/// Horizontal scrolling avatar quick selector
public struct AvatarQuickSelect: View {
    let username: String
    @Binding var selectedAvatarId: String?
    var showAllButton: (() -> Void)?
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    
    // Show a mix of popular avatars
    private var quickAvatars: [PresetAvatar] {
        var avatars: [PresetAvatar] = []
        avatars.append(contentsOf: AvatarCatalog.cryptoAvatars.prefix(3))
        avatars.append(contentsOf: AvatarCatalog.animalAvatars.prefix(3))
        avatars.append(contentsOf: AvatarCatalog.abstractAvatars.prefix(2))
        return avatars
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Choose Avatar")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                if let showAllButton = showAllButton {
                    Button("See All") {
                        showAllButton()
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.yellow)
                }
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Initials option
                    Button {
                        withAnimation { selectedAvatarId = nil }
                    } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                UserAvatarView(
                                    username: username,
                                    avatarPresetId: nil,
                                    size: 50
                                )
                                
                                if selectedAvatarId == nil {
                                    Circle()
                                        .strokeBorder(Color.yellow, lineWidth: 2)
                                        .frame(width: 54, height: 54)
                                }
                            }
                            
                            Text("Initials")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(selectedAvatarId == nil ? .primary : .secondary)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Quick avatars
                    ForEach(quickAvatars) { avatar in
                        Button {
                            withAnimation { selectedAvatarId = avatar.id }
                        } label: {
                            VStack(spacing: 4) {
                                ZStack {
                                    ZStack {
                                        avatar.gradient
                                        
                                        if let assetName = avatar.assetImageName {
                                            Image(assetName)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 30, height: 30)
                                                .clipShape(Circle())
                                        } else {
                                            Image(systemName: avatar.iconName)
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundColor(.white)
                                        }
                                    }
                                    .frame(width: 50, height: 50)
                                    .clipShape(Circle())
                                    
                                    if selectedAvatarId == avatar.id {
                                        Circle()
                                            .strokeBorder(Color.yellow, lineWidth: 2)
                                            .frame(width: 54, height: 54)
                                    }
                                }
                                
                                Text(avatar.name)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(selectedAvatarId == avatar.id ? .primary : .secondary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct AvatarPickerView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            AvatarPickerView(
                username: "SwiftFox",
                selectedAvatarId: .constant("crypto_bitcoin")
            )
            .preferredColorScheme(.dark)
            
            CompactAvatarPicker(
                username: "BoldWhale",
                selectedAvatarId: .constant(nil)
            )
            .padding()
            .background(Color.black)
            .preferredColorScheme(.dark)
            
            AvatarQuickSelect(
                username: "CryptoLion",
                selectedAvatarId: .constant("animal_lion")
            ) {
                print("Show all tapped")
            }
            .padding()
            .background(Color.black)
            .preferredColorScheme(.dark)
        }
    }
}
#endif
