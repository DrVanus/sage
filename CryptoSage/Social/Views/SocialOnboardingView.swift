//
//  SocialOnboardingView.swift
//  CryptoSage
//
//  Optional social profile setup flow shown after account creation.
//  Allows users to quickly set up their avatar and username.
//

import SwiftUI

// MARK: - Social Onboarding View

/// Optional social setup flow for new users
public struct SocialOnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @StateObject private var socialService = SocialService.shared
    @StateObject private var usernameVM = UsernameViewModel()
    
    @State private var currentStep: OnboardingStep = .welcome
    @State private var selectedAvatarId: String? = nil
    @State private var customUsername: String = ""
    @State private var useCustomUsername: Bool = false
    @State private var joinLeaderboard: Bool = false
    @State private var isCreating: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    
    let onComplete: () -> Void
    let onSkip: () -> Void
    
    private var isDark: Bool { colorScheme == .dark }
    
    public init(onComplete: @escaping () -> Void, onSkip: @escaping () -> Void) {
        self.onComplete = onComplete
        self.onSkip = onSkip
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                // Background
                (isDark ? Color.black : Color(UIColor.systemBackground))
                    .ignoresSafeArea()
                
                // Content
                VStack(spacing: 0) {
                    // Progress indicator
                    progressIndicator
                        .padding(.top, 16)
                    
                    // Step content
                    TabView(selection: $currentStep) {
                        welcomeStep.tag(OnboardingStep.welcome)
                        avatarStep.tag(OnboardingStep.avatar)
                        usernameStep.tag(OnboardingStep.username)
                        leaderboardStep.tag(OnboardingStep.leaderboard)
                        completeStep.tag(OnboardingStep.complete)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.easeInOut(duration: 0.3), value: currentStep)
                    
                    // Navigation buttons
                    navigationButtons
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Skip") {
                        onSkip()
                        dismiss()
                    }
                    .foregroundColor(.secondary)
                }
            }
            .toolbarBackground(isDark ? Color.black : Color(UIColor.systemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(isDark ? .dark : .light, for: .navigationBar)
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    // MARK: - Progress Indicator
    
    private var progressIndicator: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                Capsule()
                    .fill(step.rawValue <= currentStep.rawValue ? Color.yellow : Color.gray.opacity(0.3))
                    .frame(width: step.rawValue <= currentStep.rawValue ? 24 : 8, height: 4)
                    .animation(.easeInOut(duration: 0.3), value: currentStep)
            }
        }
    }
    
    // MARK: - Welcome Step
    
    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Icon
            ZStack {
                Circle()
                    .fill(Color.yellow.opacity(0.15))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "person.2.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.yellow)
            }
            
            Text("Join the Community")
                .font(.title.weight(.bold))
            
            Text("Set up your social profile to compete on leaderboards, share trading strategies, and connect with other traders.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            // Quick features
            VStack(alignment: .leading, spacing: 16) {
                featureRow(icon: "trophy.fill", color: .yellow, text: "Compete on leaderboards")
                featureRow(icon: "square.and.arrow.up.fill", color: .blue, text: "Share your trading bots")
                featureRow(icon: "person.2.fill", color: .green, text: "Follow top traders")
            }
            .padding(.top, 16)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Avatar Step
    
    private var avatarStep: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Text("Choose Your Avatar")
                .font(.title2.weight(.bold))
            
            Text("Pick an icon that represents you, or use your initials.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            // Large preview
            UserAvatarView(
                username: effectiveUsername,
                avatarPresetId: selectedAvatarId,
                size: 100,
                showRing: true,
                ringColor: .yellow
            )
            .padding(.vertical, 16)
            
            // Quick avatar selection
            AvatarQuickSelect(
                username: effectiveUsername,
                selectedAvatarId: $selectedAvatarId
            )
            .padding(.horizontal)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Username Step
    
    private var usernameStep: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Your Username")
                    .font(.title2.weight(.bold))
                    .padding(.top, 20)
                
                Text("This is how other traders will see you on the leaderboard.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                
                // Current username preview
                VStack(spacing: 8) {
                    UserAvatarView(
                        username: effectiveUsername,
                        avatarPresetId: selectedAvatarId,
                        size: 60
                    )
                    
                    Text("@\(effectiveUsername)")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                .padding(.vertical, 16)
                
                // Suggested usernames
                VStack(alignment: .leading, spacing: 12) {
                    Text("Suggested usernames")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                    
                    FlowLayout(spacing: 8) {
                        ForEach(usernameVM.suggestions, id: \.self) { suggestion in
                            Button {
                                usernameVM.selectSuggestion(suggestion)
                                customUsername = suggestion.lowercased()
                                useCustomUsername = true
                            } label: {
                                Text(suggestion)
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule()
                                            .fill(customUsername.lowercased() == suggestion.lowercased()
                                                ? Color.yellow.opacity(0.2)
                                                : (isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05)))
                                    )
                                    .overlay(
                                        Capsule()
                                            .stroke(customUsername.lowercased() == suggestion.lowercased()
                                                ? Color.yellow : Color.clear, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    
                    Button {
                        usernameVM.generateSuggestions()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Generate new suggestions")
                        }
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    }
                    .padding(.top, 4)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
                )
                .padding(.horizontal)
                
                // Custom username input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Or enter your own")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.secondary)
                    
                    HStack {
                        Text("@")
                            .foregroundColor(.secondary)
                        
                        TextField("username", text: $customUsername)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .onChange(of: customUsername) { _, _ in
                                useCustomUsername = !customUsername.isEmpty
                            }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
                    )
                }
                .padding(.horizontal)
                
                Spacer(minLength: 50)
            }
        }
    }
    
    // MARK: - Leaderboard Step
    
    private var leaderboardStep: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Trophy icon
            ZStack {
                Circle()
                    .fill(Color.yellow.opacity(0.15))
                    .frame(width: 100, height: 100)
                
                Image(systemName: "trophy.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.yellow)
            }
            
            Text("Join the Leaderboard?")
                .font(.title2.weight(.bold))
            
            Text("Compete with other traders and track your rank based on your paper trading performance.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            // Benefits
            VStack(alignment: .leading, spacing: 12) {
                benefitRow(icon: "chart.line.uptrend.xyaxis", text: "Track your trading progress")
                benefitRow(icon: "star.fill", text: "Earn badges and achievements")
                benefitRow(icon: "person.3.fill", text: "See how you rank globally")
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)
            
            // Toggle
            Toggle(isOn: $joinLeaderboard) {
                HStack {
                    Image(systemName: joinLeaderboard ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(joinLeaderboard ? .green : .secondary)
                    
                    Text("Yes, add me to the leaderboard")
                        .font(.headline)
                }
            }
            .toggleStyle(.button)
            .buttonStyle(.plain)
            .padding(.horizontal, 32)
            .padding(.top, 24)
            
            Text("You can change this anytime in settings")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Complete Step
    
    private var completeStep: some View {
        VStack(spacing: 24) {
            Spacer()
            
            // Success animation
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
            }
            
            Text("You're All Set!")
                .font(.title.weight(.bold))
            
            // Profile preview
            VStack(spacing: 12) {
                UserAvatarView(
                    username: effectiveUsername,
                    avatarPresetId: selectedAvatarId,
                    size: 80,
                    showRing: true,
                    ringColor: .yellow
                )
                
                Text("@\(effectiveUsername)")
                    .font(.headline)
                
                if joinLeaderboard {
                    HStack(spacing: 4) {
                        Image(systemName: "trophy.fill")
                            .foregroundColor(.yellow)
                        Text("Competing on leaderboard")
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
            )
            
            Spacer()
        }
        .padding()
    }
    
    // MARK: - Navigation Buttons
    
    private var navigationButtons: some View {
        HStack(spacing: 16) {
            // Back button (not on first step)
            if currentStep != .welcome {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation {
                        currentStep = currentStep.previous
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(DS.Adaptive.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.04))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(BrandColors.goldBase.opacity(isDark ? 0.12 : 0.08), lineWidth: 0.8)
                    )
                }
                .buttonStyle(.plain)
            }
            
            // Next/Complete button
            Button {
                handleNextButton()
            } label: {
                HStack {
                    if isCreating {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Text(currentStep == .complete ? "Get Started" : "Continue")
                        
                        if currentStep != .complete {
                            Image(systemName: "chevron.right")
                        }
                    }
                }
                .font(.headline)
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.yellow)
                )
            }
            .disabled(isCreating)
        }
    }
    
    // MARK: - Helper Views
    
    private func featureRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            
            Text(text)
                .font(.body)
        }
    }
    
    private func benefitRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.yellow)
                .frame(width: 24)
            
            Text(text)
                .font(.subheadline)
        }
    }
    
    // MARK: - Computed Properties
    
    private var effectiveUsername: String {
        if useCustomUsername && !customUsername.isEmpty {
            return customUsername.lowercased()
        }
        return usernameVM.suggestions.first?.lowercased() ?? UsernameGenerator.generate().lowercased()
    }
    
    // MARK: - Actions
    
    private func handleNextButton() {
        switch currentStep {
        case .welcome, .avatar, .username, .leaderboard:
            withAnimation {
                currentStep = currentStep.next
            }
        case .complete:
            createProfile()
        }
    }
    
    private func createProfile() {
        isCreating = true
        
        Task {
            do {
                try await socialService.createOrUpdateProfile(
                    username: effectiveUsername,
                    displayName: nil,
                    avatarPresetId: selectedAvatarId,
                    bio: nil,
                    isPublic: true,
                    showOnLeaderboard: joinLeaderboard,
                    leaderboardMode: joinLeaderboard ? .paperOnly : .none,
                    liveTrackingConsent: false,
                    primaryTradingMode: .paper,
                    socialLinks: nil
                )
                
                await MainActor.run {
                    isCreating = false
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onComplete()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }
}

// MARK: - Onboarding Step

private enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case avatar = 1
    case username = 2
    case leaderboard = 3
    case complete = 4
    
    var next: OnboardingStep {
        OnboardingStep(rawValue: rawValue + 1) ?? .complete
    }
    
    var previous: OnboardingStep {
        OnboardingStep(rawValue: rawValue - 1) ?? .welcome
    }
}

// MARK: - Preview
// Note: FlowLayout is defined in MarketFilterSheet.swift and reused here

#if DEBUG
struct SocialOnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        SocialOnboardingView(
            onComplete: { print("Completed") },
            onSkip: { print("Skipped") }
        )
        .preferredColorScheme(.dark)
    }
}
#endif
