//
//  HomeHeaderBar.swift
//  CryptoSage
//
//  Compact header with user avatar, collapsible trading mode toggle, and action buttons.
//  Expanded: full toggle inline.  Collapsed: premium "Flux Beacon" — animated scanning ring,
//  glass depth layers, luminous mode icon with breathing glow.
//  Tapping the avatar opens Settings.
//

import SwiftUI
import Combine

struct HomeHeaderBar: View {
    @Binding var showNotifications: Bool
    @Binding var showSettings: Bool
    var hasPendingNotifications: Bool = false
    var onNotifications: (() -> Void)? = nil
    var onSettings: (() -> Void)? = nil
    
    // Mode management
    @ObservedObject private var paperTradingManager = PaperTradingManager.shared
    @ObservedObject private var demoModeManager = DemoModeManager.shared
    
    // Observe ProfileSyncService so the greeting re-renders when cloud data is restored
    @ObservedObject private var profileSync = ProfileSyncService.shared
    
    // Persisted expand/collapse state
    @AppStorage("headerModeToggleExpanded") private var isExpanded: Bool = true
    
    // User profile name for greeting
    @AppStorage("profile.displayName") private var displayName: String = ""
    
    // Paywall
    @State private var showUpgradeSheet = false
    
    // Sliding pill + expand/collapse animation namespace
    @Namespace private var modeToggleNamespace
    
    // Staggered button reveal
    @State private var buttonsRevealed: Bool = false
    
    // Collapsed beacon animations
    @State private var ringRotation: Double = 0
    @State private var glowPulse: Double = 0.12
    @State private var beaconAnimating: Bool = false
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var isDark: Bool { colorScheme == .dark }
    private let buttonSize: CGFloat = 34
    
    /// Current trading mode
    private var currentMode: AppTradingMode {
        if paperTradingManager.isPaperTradingEnabled { return .paper }
        if demoModeManager.isDemoMode { return .demo }
        if SubscriptionManager.shared.isDeveloperMode && SubscriptionManager.shared.developerLiveTradingEnabled {
            return .liveTrading
        }
        return .portfolio
    }
    
    /// Check if user has connected exchange accounts
    private var hasConnectedAccounts: Bool {
        !ConnectedAccountsManager.shared.accounts.isEmpty
    }
    
    /// Check if developer mode is active
    private var isDeveloperMode: Bool {
        SubscriptionManager.shared.isDeveloperMode
    }
    
    /// Available modes — developers get all modes; regular users see Demo when they have no accounts
    var availableModes: [AppTradingMode] {
        var modes: [AppTradingMode] = [.portfolio, .paper]
        
        // Demo is available for:
        // - Developers (for testing/exploring sample data)
        // - Regular users who haven't connected an exchange yet
        if isDeveloperMode || (!hasConnectedAccounts && !paperTradingManager.isPaperTradingEnabled) {
            modes.append(.demo)
        }
        
        // Live Trading only for developers (real money execution)
        if isDeveloperMode {
            modes.append(.liveTrading)
        }
        
        return modes
    }
    
    var body: some View {
        HStack(spacing: 8) {
            // Left: Profile avatar (taps to open settings)
            avatarButton
            
            // Center: Beacon+greeting (collapsed) or toggle bar (expanded).
            // When collapsed, beacon + greeting sit in an HStack flush-left.
            // When expanded, the full toggle bar replaces them.
            ZStack(alignment: .leading) {
                // Collapsed: beacon icon + greeting in a compact HStack
                if !isExpanded {
                    HStack(spacing: 8) {
                        modeIconButton
                        greetingLabel
                            .transition(
                                .asymmetric(
                                    insertion: .opacity
                                        .combined(with: .move(edge: .leading))
                                        .combined(with: .scale(scale: 0.85, anchor: .leading)),
                                    removal: .opacity
                                        .combined(with: .scale(scale: 0.9, anchor: .leading))
                                )
                            )
                    }
                    .transition(
                        .asymmetric(
                            insertion: .opacity.animation(.easeOut(duration: 0.35).delay(0.08)),
                            removal: .opacity.animation(.easeIn(duration: 0.2))
                        )
                    )
                }
                
                // Expanded: full toggle bar
                if isExpanded {
                    inlineModeToggle
                        .transition(
                            .asymmetric(
                                insertion: .opacity.animation(.easeOut(duration: 0.3).delay(0.05)),
                                removal: .opacity.animation(.easeIn(duration: 0.2))
                            )
                        )
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.82), value: isExpanded)
            .onAppear {
                // If toggle is already expanded on launch, show buttons instantly.
                // .onChange won't fire for the initial value, so we handle it here.
                // No animation — buttons must be at final positions immediately so
                // matchedGeometryEffect anchors are correct from the start.
                if isExpanded {
                    buttonsRevealed = true
                }
            }
            .onChange(of: isExpanded) { _, expanded in
                if expanded {
                    // Stagger the button content reveal after expand
                    buttonsRevealed = false
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.78).delay(0.1)) {
                        buttonsRevealed = true
                    }
                } else {
                    buttonsRevealed = false
                }
            }
            
            Spacer(minLength: 4)
            
            // Right: Notification + Settings buttons
            HStack(spacing: 6) {
                notificationButton
                settingsButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .contentShape(Rectangle())
        .sheet(isPresented: $showUpgradeSheet) {
            UnifiedPaywallSheet(feature: .paperTrading)
        }
    }
    
    // MARK: - Avatar Button
    
    @ViewBuilder
    private var avatarButton: some View {
        Button {
            onSettings?()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showSettings = true
        } label: {
            ProfileAvatarMini(size: 34)
        }
        .buttonStyle(ProfileButtonStyle())
        .accessibilityLabel("Profile")
        .accessibilityHint("Double tap to open settings")
    }
    
    // MARK: - Collapsed Mode Beacon
    
    /// Premium "Flux Beacon" — a high-tech collapsed mode indicator with:
    /// - Animated scanning light border (rotating angular gradient)
    /// - Multi-layer glass depth (radial + linear gradient fills)
    /// - Luminous icon with color-matched glow
    /// - Soft breathing outer shadow
    /// Tap to expand the full mode toggle.
    @ViewBuilder
    private var modeIconButton: some View {
        let modeColor = currentMode.color
        let beaconSize: CGFloat = 34
        
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.72)) {
                isExpanded = true
            }
        } label: {
            ZStack {
                // ── Layer 1: Glass fill with radial glow from icon center ──
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                modeColor.opacity(isDark ? 0.18 : 0.16),
                                modeColor.opacity(isDark ? 0.06 : 0.05),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: beaconSize * 0.6
                        )
                    )
                
                // ── Layer 2: Top-highlight for glass depth ──
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isDark ? [
                                Color.white.opacity(0.07),
                                Color.white.opacity(0.0)
                            ] : [
                                Color.white.opacity(0.55),
                                Color.white.opacity(0.08)
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                
                // ── Layer 3: Animated scanning ring ──
                // Light mode: boosted opacity so the beam is clearly visible on white backgrounds
                Circle()
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(stops: [
                                .init(color: modeColor.opacity(isDark ? 0.85 : 0.80), location: 0.0),
                                .init(color: modeColor.opacity(isDark ? 0.3 : 0.35), location: 0.08),
                                .init(color: .clear, location: 0.20),
                                .init(color: .clear, location: 0.80),
                                .init(color: modeColor.opacity(isDark ? 0.3 : 0.35), location: 0.92),
                                .init(color: modeColor.opacity(isDark ? 0.85 : 0.80), location: 1.0),
                            ]),
                            center: .center,
                            angle: .degrees(ringRotation)
                        ),
                        lineWidth: isDark ? 1.5 : 1.8
                    )
                
                // ── Layer 4: Static base ring — stronger in light mode for definition ──
                Circle()
                    .stroke(
                        modeColor.opacity(isDark ? 0.25 : 0.30),
                        lineWidth: isDark ? 0.5 : 0.75
                    )
                
                // ── Layer 5: Mode icon with luminous treatment ──
                Image(systemName: currentMode.icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: isDark ? [
                                modeColor,
                                modeColor.opacity(0.75)
                            ] : [
                                modeColor,
                                modeColor.opacity(0.85)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
            .frame(width: beaconSize, height: beaconSize)
        }
        .buttonStyle(.plain)
        // Breathing outer glow — slightly more visible in light mode
        .onAppear { startBeaconAnimations() }
        .onDisappear { beaconAnimating = false }
        .accessibilityLabel("Current mode: \(currentMode.rawValue). Tap to expand mode selector.")
    }
    
    /// Kicks off the beacon's ambient animations — scanning ring + breathing glow.
    /// Designed to be lightweight (GPU-composited gradients, no layout changes).
    private func startBeaconAnimations() {
        guard !beaconAnimating else { return }
        // MEMORY FIX v9: Block .repeatForever animations during startup suppression window.
        // HomeHeaderBar is always visible, so its continuous animations would run from t=0.
        // MEMORY FIX v10: NO retry — beacon starts when user scrolls home
        guard !shouldSuppressStartupAnimations() else { return }
        beaconAnimating = true
        
        // Scanning ring rotation — slow, continuous, mesmerizing
        withAnimation(.linear(duration: 3.5).repeatForever(autoreverses: false)) {
            ringRotation = 360
        }
        
        // Breathing glow — subtle pulse that gives the beacon a "living" quality
        withAnimation(.easeInOut(duration: 2.8).repeatForever(autoreverses: true)) {
            glowPulse = isDark ? 0.35 : 0.22
        }
    }
    
    // MARK: - Greeting Label (collapsed state)
    
    /// Time-of-day greeting with optional user name, shown when mode toggle is collapsed.
    /// Single line, compact — fits naturally in the header without competing for space.
    @ViewBuilder
    private var greetingLabel: some View {
        let firstName = displayName.components(separatedBy: " ").first ?? ""
        let hasName = !firstName.isEmpty
        let text = hasName ? "\(timeOfDayGreeting), \(firstName)" : timeOfDayGreeting
        
        Text(text)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(isDark ? Color.white.opacity(0.55) : DS.Adaptive.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.leading, 6)
    }
    
    /// Returns a time-of-day greeting string
    private var timeOfDayGreeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        case 17..<22: return "Good evening"
        default:       return "Good evening"
        }
    }
    
    // MARK: - Expanded Inline Mode Toggle
    
    /// Premium mode toggle bar — glass container with a true sliding pill.
    /// The pill is a single view that uses matchedGeometryEffect source/destination
    /// to smoothly glide between button positions (e.g. Portfolio → Demo slides through Paper).
    @ViewBuilder
    private var inlineModeToggle: some View {
        HStack(spacing: isCompactToggle ? 2 : 3) {
            ForEach(Array(availableModes.enumerated()), id: \.element.id) { index, mode in
                inlineModeButton(for: mode)
                    // Each button places an invisible anchor for the sliding pill
                    .background(
                        Capsule()
                            .fill(Color.clear)
                            .matchedGeometryEffect(id: "btn_\(mode.rawValue)", in: modeToggleNamespace, isSource: true)
                    )
                    .opacity(buttonsRevealed ? 1 : 0)
                    .scaleEffect(buttonsRevealed ? 1 : 0.7)
                    .animation(
                        .spring(response: 0.35, dampingFraction: 0.72)
                            .delay(Double(index) * 0.04),
                        value: buttonsRevealed
                    )
            }
            
            // Integrated collapse divider + chevron
            collapseButton
                .opacity(buttonsRevealed ? 1 : 0)
                .animation(
                    .spring(response: 0.35, dampingFraction: 0.72)
                        .delay(Double(availableModes.count) * 0.04),
                    value: buttonsRevealed
                )
        }
        .padding(3)
        // The single sliding pill — always present, slides to current mode's anchor
        .background(
            slidingPill
                .matchedGeometryEffect(id: "btn_\(currentMode.rawValue)", in: modeToggleNamespace, isSource: false)
                .animation(.spring(response: 0.4, dampingFraction: 0.72), value: currentMode)
                .padding(3)
        )
        .background(
            ZStack {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: isDark ? [
                                Color.white.opacity(0.06),
                                Color.white.opacity(0.02)
                            ] : [
                                BrandColors.goldDark.opacity(0.04),
                                BrandColors.goldDark.opacity(0.015)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                // Subtle inner glow for depth
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(isDark ? 0.03 : 0.12), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
            }
        )
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: isDark ? [
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.04)
                        ] : [
                            BrandColors.goldDark.opacity(0.12),
                            BrandColors.goldDark.opacity(0.04)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: isDark ? 0.5 : 0.75
                )
        )
    }
    
    /// Integrated collapse button — a thin divider line + chevron that feels part of the toggle.
    @ViewBuilder
    private var collapseButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                isExpanded = false
            }
        } label: {
            HStack(spacing: 0) {
                // Thin divider line
                Rectangle()
                    .fill(isDark ? Color.white.opacity(0.10) : BrandColors.goldDark.opacity(0.10))
                    .frame(width: 0.5, height: 16)
                    .padding(.trailing, 6)
                
                // Chevron icon
                Image(systemName: "chevron.left")
                    .font(.system(size: 9, weight: .heavy))
                    .foregroundStyle(
                        LinearGradient(
                            colors: isDark
                                ? [Color.white.opacity(0.35), Color.white.opacity(0.20)]
                                : [BrandColors.goldDark.opacity(0.45), BrandColors.goldDark.opacity(0.25)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .padding(.trailing, 6)
            .padding(.vertical, 7)
            .contentShape(Rectangle().inset(by: -4))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Collapse mode switcher")
    }
    
    /// The sliding glass pill — a single view that glides behind the selected button.
    /// Uses the current mode's color for the glass fill and border.
    private var slidingPill: some View {
        let c = currentMode.color
        return ZStack {
            // Glass fill with radial center glow
            Capsule()
                .fill(
                    RadialGradient(
                        colors: [
                            c.opacity(isDark ? 0.22 : 0.16),
                            c.opacity(isDark ? 0.08 : 0.04)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 50
                    )
                )
            
            // Top shine for glass depth
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isDark ? 0.10 : 0.25),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: UnitPoint(x: 0.5, y: 0.45)
                    )
                )
                .padding(1)
            
            // Gradient border ring
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [
                            c.opacity(isDark ? 0.75 : 0.65),
                            c.opacity(isDark ? 0.35 : 0.30)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }
    
    /// Individual mode button — text and icon only (the glass pill slides behind via slidingPill).
    /// Selected: luminous text + icon glow. Unselected: subtle secondary text.
    /// Whether we need a tighter layout (4+ modes, e.g. developer mode)
    private var isCompactToggle: Bool { availableModes.count > 3 }
    
    @ViewBuilder
    private func inlineModeButton(for mode: AppTradingMode) -> some View {
        let isSelected = currentMode == mode
        let isLocked = mode == .paper && !paperTradingManager.hasAccess
        let modeColor = mode.color
        
        if isCompactToggle {
            // ── Developer mode (4+ modes) ──
            // All buttons show compact labels (icon-only was invisible).
            // Tighter padding so 4 labeled buttons fit side-by-side.
            compactModeButton(
                mode: mode, isSelected: isSelected, isLocked: isLocked, modeColor: modeColor
            )
        } else {
            // ── Normal mode (≤3 modes) — ORIGINAL layout, untouched ──
            let showLabel = true  // Always show labels in normal mode
            
            Button {
                if isLocked {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showUpgradeSheet = true
                } else {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        selectMode(mode)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    // Icon — luminous gradient for selected, flat for unselected
                    Image(systemName: mode.icon)
                        .font(.system(size: 10, weight: isSelected ? .bold : .semibold))
                        .foregroundStyle(
                            isSelected
                                ? AnyShapeStyle(LinearGradient(
                                    colors: [modeColor, modeColor.opacity(0.75)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                  ))
                                : AnyShapeStyle(isLocked
                                    ? Color.secondary.opacity(0.3)
                                    : Color.secondary.opacity(0.55))
                        )
                    
                    // Label — in normal mode all buttons show full label
                    if showLabel {
                        Text(mode.rawValue)
                            .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .rounded))
                            .foregroundColor(
                                isSelected
                                    ? modeColor
                                    : (isLocked ? .secondary.opacity(0.3) : .secondary.opacity(0.55))
                            )
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    
                    if isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundColor(.secondary.opacity(0.3))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
            }
            .buttonStyle(ModeButtonPressStyle())
        }
    }
    
    // MARK: - Compact Mode Button (Developer mode only, 4+ modes)
    
    /// Separate function so changes here NEVER affect normal (≤3 mode) layout.
    @ViewBuilder
    private func compactModeButton(
        mode: AppTradingMode,
        isSelected: Bool,
        isLocked: Bool,
        modeColor: Color
    ) -> some View {
        Button {
            if isLocked {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showUpgradeSheet = true
            } else {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    selectMode(mode)
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: mode.icon)
                    .font(.system(size: 9, weight: isSelected ? .bold : .semibold))
                    .foregroundStyle(
                        isSelected
                            ? AnyShapeStyle(LinearGradient(
                                colors: [modeColor, modeColor.opacity(0.75)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                              ))
                            : AnyShapeStyle(isLocked
                                ? Color.secondary.opacity(0.3)
                                : Color.secondary.opacity(0.65))
                    )
                
                // Always show compact label so all buttons are identifiable
                Text(mode.compactLabel)
                    .font(.system(size: 9.5, weight: isSelected ? .bold : .medium, design: .rounded))
                    .foregroundColor(
                        isSelected
                            ? modeColor
                            : (isLocked ? .secondary.opacity(0.3) : .secondary.opacity(0.65))
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 5, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.3))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
        }
        .buttonStyle(ModeButtonPressStyle())
    }
    
    // MARK: - Mode Selection Logic
    
    private func selectMode(_ mode: AppTradingMode) {
        DispatchQueue.main.async {
            switch mode {
            case .portfolio:
                self.paperTradingManager.disablePaperTrading()
                self.demoModeManager.disableDemoMode()
                if self.isDeveloperMode {
                    SubscriptionManager.shared.developerLiveTradingEnabled = false
                }
            case .paper:
                self.demoModeManager.disableDemoMode()
                _ = self.paperTradingManager.enablePaperTrading()
                if self.isDeveloperMode {
                    SubscriptionManager.shared.developerLiveTradingEnabled = false
                }
            case .liveTrading:
                self.paperTradingManager.disablePaperTrading()
                self.demoModeManager.disableDemoMode()
                SubscriptionManager.shared.developerLiveTradingEnabled = true
            case .demo:
                self.paperTradingManager.disablePaperTrading()
                self.demoModeManager.enableDemoMode()
                if self.isDeveloperMode {
                    SubscriptionManager.shared.developerLiveTradingEnabled = false
                }
            }
        }
    }
    
    // MARK: - Action Buttons
    
    @ViewBuilder
    private var notificationButton: some View {
        Button {
            onNotifications?()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showNotifications = true
        } label: {
            ZStack(alignment: .topTrailing) {
                GlassButton(
                    icon: "bell",
                    size: buttonSize
                )
                
                // Notification badge
                if hasPendingNotifications {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .overlay(
                            Circle()
                                .stroke(DS.Adaptive.background, lineWidth: 1.5)
                        )
                        .offset(x: 1, y: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Notifications")
        .accessibilityHint(hasPendingNotifications ? "You have unread notifications" : "No new notifications")
    }
    
    @ViewBuilder
    private var settingsButton: some View {
        Button {
            onSettings?()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showSettings = true
        } label: {
            GlassButton(
                icon: "gearshape",
                size: buttonSize
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
        .accessibilityHint("Double tap to open settings")
    }
}

// MARK: - Premium Glass Icon Button

/// High-quality glass button matching the header's premium design language.
/// Multi-layer depth: radial fill + top shine + gradient border + luminous icon + breathing glow.
private struct GlassButton: View {
    let icon: String
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme
    @State private var glowPulse: Double = 0.04
    
    private var isDark: Bool { colorScheme == .dark }
    
    // Accent color — white glow in dark, warm bronze in light for contrast on white backgrounds
    private var accentColor: Color {
        isDark ? Color.white : BrandColors.goldDark
    }
    
    var body: some View {
        ZStack {
            // ── Layer 1: Glass fill with radial depth ──
            Circle()
                .fill(
                    RadialGradient(
                        colors: isDark ? [
                            Color.white.opacity(0.10),
                            Color.white.opacity(0.04),
                            Color.clear
                        ] : [
                            BrandColors.goldDark.opacity(0.06),
                            BrandColors.goldDark.opacity(0.02),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.55
                    )
                )
            
            // ── Layer 2: Top-highlight glass shine ──
            Circle()
                .fill(
                    LinearGradient(
                        colors: isDark ? [
                            Color.white.opacity(0.09),
                            Color.clear
                        ] : [
                            Color.white.opacity(0.60),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            
            // ── Layer 3: Gradient border ring — bronze in light mode ──
            Circle()
                .stroke(
                    LinearGradient(
                        colors: isDark ? [
                            Color.white.opacity(0.20),
                            Color.white.opacity(0.06)
                        ] : [
                            BrandColors.goldDark.opacity(0.35),
                            BrandColors.goldBase.opacity(0.15)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: isDark ? 0.75 : 1.0
                )
            
            // ── Layer 4: Luminous icon — uses gold gradient in light mode ──
            Image(systemName: icon)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(
                    isDark
                        ? AnyShapeStyle(LinearGradient(
                            colors: [Color.white.opacity(0.80), Color.white.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                          ))
                        : AnyShapeStyle(LinearGradient(
                            colors: [BrandColors.goldDark, BrandColors.goldDark.opacity(0.70)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                          ))
                )
        }
        .frame(width: size, height: size)
        // Subtle breathing glow — ties into the header's living quality
        .contentShape(Circle())
        .onAppear {
            // MEMORY FIX v9: Block during startup animation suppression window
            guard !shouldSuppressStartupAnimations() else { return }
            withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) {
                glowPulse = isDark ? 0.15 : 0.10
            }
        }
    }
}

// MARK: - Button Styles

private struct ProfileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

private struct ModeButtonPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#Preview {
    VStack(spacing: 20) {
        HomeHeaderBar(
            showNotifications: .constant(false),
            showSettings: .constant(false),
            hasPendingNotifications: true
        )
        
        HomeHeaderBar(
            showNotifications: .constant(false),
            showSettings: .constant(false),
            hasPendingNotifications: false
        )
        
        Spacer()
    }
    .background(DS.Adaptive.background)
    .preferredColorScheme(.dark)
}
